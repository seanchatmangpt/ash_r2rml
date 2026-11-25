# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer: AshPostgres. Implements the layer module contract
# (available?/0, setup/1, scenarios/0, canonical_digest/1) as Bench.Layer.Postgres.
#
# Needs ASH_R2RML_POSTGRES_URL (else {:skip, reason}). Real AshPostgres repo, pool_size 4,
# `:attribute` multitenancy over 10 tenants (t0..t9), read policy `tenant_id == actor.tenant`.
#
# Seed shape: tenant t0 holds exactly `digest_rows` (default 500) rows pid "p1".."pN", name
# "Person i", age i (the cross-layer digest tenant). Tenants t1..t9 hold load rows with pid
# "t<k>-p<i>" and name "t<k> Person <i>", so every subject IRI names its owning tenant and a
# cross-tenant leak is detectable from the subject alone.
#
# Waiting is deadline-polled on a real observable (pg_stat_activity); the only sleep is the
# poll step inside await_idle/2.

if Code.ensure_loaded?(AshPostgres.DataLayer) do
  defmodule Bench.Layer.Postgres.Repo do
    use AshPostgres.Repo, otp_app: :ash_r2rml, warn_on_missing_ash_functions?: false

    def installed_extensions, do: []
    def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  end

  defmodule Bench.Layer.Postgres.Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource Bench.Layer.Postgres.Person
    end
  end

  defmodule Bench.Layer.Postgres.Person do
    use Ash.Resource,
      domain: Bench.Layer.Postgres.Domain,
      data_layer: AshPostgres.DataLayer,
      authorizers: [Ash.Policy.Authorizer],
      extensions: [AshR2RML]

    postgres do
      table "bench_stress_people"
      repo Bench.Layer.Postgres.Repo
    end

    r2rml do
      class_iri("https://ex.org/Person")
      subject_template("https://ex.org/person/{pid}")
      table_name("person")

      attribute_mappings([
        {:name, "https://schema.org/name"},
        {:age, "https://schema.org/age"}
      ])
    end

    multitenancy do
      strategy :attribute
      attribute :tenant_id
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:pid, :name, :age]
      end
    end

    policies do
      policy action_type([:create, :update, :destroy]) do
        authorize_if always()
      end

      policy action_type(:read) do
        authorize_if expr(tenant_id == ^actor(:tenant))
      end
    end

    attributes do
      attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :tenant_id, :string, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
      attribute :age, :integer, public?: true
    end

    identities do
      identity :by_pid, [:pid]
    end
  end
end

defmodule Bench.Layer.Postgres do
  @moduledoc false

  alias AshR2RML.OBDA
  alias Bench.Layer.Common

  @repo Bench.Layer.Postgres.Repo
  @domain Bench.Layer.Postgres.Domain
  @resource Bench.Layer.Postgres.Person

  @tenants for k <- 0..9, do: "t#{k}"
  @digest_tenant "t0"
  @prefix "https://ex.org/person/"
  @callers 64
  @killers 32
  @calls_each 3

  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"

  @ddl_drop "DROP TABLE IF EXISTS bench_stress_people"
  @ddl_create "CREATE TABLE bench_stress_people (pid TEXT PRIMARY KEY NOT NULL, " <>
                "tenant_id TEXT NOT NULL, name TEXT, age BIGINT)"
  @ddl_index "CREATE INDEX bench_stress_people_tenant ON bench_stress_people (tenant_id)"

  # {opts, codes the isolated scenario must return}
  @killers_isolated [
    s1_memory: {[max_heap_words: 2_000], [:REFUSED_MEMORY_LIMIT_EXCEEDED]},
    s2_row_limit: {[max_rows: 10], [:REFUSED_RESULT_LIMIT_EXCEEDED]},
    s3_triple_limit: {[max_triples: 50], [:REFUSED_TRIPLE_LIMIT_EXCEEDED]},
    s4_timeout: {[timeout_ms: 1], [:REFUSED_QUERY_TIMEOUT]}
  ]

  # ---- contract ----

  def available? do
    cond do
      System.get_env("ASH_R2RML_POSTGRES_URL") in [nil, ""] ->
        {:skip, "ASH_R2RML_POSTGRES_URL is not set"}

      not Code.ensure_loaded?(AshPostgres.DataLayer) ->
        {:skip, "ash_postgres is not loaded"}

      not Code.ensure_loaded?(Bench.Layer.Common) ->
        {:skip, "Bench.Layer.Common is not loaded"}

      true ->
        :ok
    end
  end

  def setup(opts) do
    with :ok <- available?() do
      boot(opts)
    end
  end

  def scenarios do
    isolated =
      for {id, {query_opts, codes}} <- @killers_isolated do
        {id, "killer #{inspect(query_opts)} refuses #{inspect(codes)} on postgres",
         fn ctx -> killer_scenario(ctx, query_opts, codes) end}
      end

    isolated ++
      [
        {:s5_mini_storm, "16 callers, mixed killer/healthy: killers typed, healthy exact, no leak",
         fn ctx -> storm(ctx, 16, 8) end},
        {:s6_policy_fail_closed, "wrong actor / nil actor / no tenant never publish rows",
         &fail_closed/1},
        {:s8_cross_tenant_storm,
         "64 callers (32 killer + 32 healthy) over 10 tenants: 0 leaks, typed refusals, 0 non-idle after",
         fn ctx -> storm(ctx, @callers, @killers, true) end}
      ]
  end

  def canonical_digest(ctx) do
    case OBDA.query(ctx.specs, @sparql, base_opts(@digest_tenant) ++ [timeout_ms: 60_000]) do
      {:ok, %AshR2RML.OBDA.Result{} = result} -> Common.digest_of(result)
      other -> raise "postgres canonical_digest: query failed: " <> inspect(other, limit: 5)
    end
  end

  # ---- setup ----

  defp boot(opts) do
    rows = Keyword.get(opts, :rows, 10_000)
    digest_rows = Keyword.get(opts, :digest_rows, 500)
    url = System.get_env("ASH_R2RML_POSTGRES_URL")
    app_name = "ash_r2rml_bench_#{System.unique_integer([:positive])}"

    with {:ok, _} <- Application.ensure_all_started(:ash_postgres),
         {:ok, repo_pid} <- start_repo(url, app_name) do
      try do
        Enum.each([@ddl_drop, @ddl_create, @ddl_index], &Ecto.Adapters.SQL.query!(@repo, &1, []))
        counts = seed!(rows, digest_rows)
        specs = [{@resource, AshR2RML.Resource.Info.mapping!(@resource)}]

        {:ok,
         %{
           specs: specs,
           domain: @domain,
           resource: @resource,
           seed_rows: counts |> Map.values() |> Enum.sum(),
           counts: counts,
           app_name: app_name,
           teardown: fn -> teardown(repo_pid) end
         }}
      catch
        kind, reason ->
          teardown(repo_pid)
          {:skip, "postgres setup failed: #{Exception.format(kind, reason)}"}
      end
    else
      {:error, reason} -> {:skip, "postgres repo did not start: #{inspect(reason)}"}
    end
  end

  defp start_repo(url, app_name) do
    case @repo.start_link(url: url, pool_size: 4, parameters: [application_name: app_name]) do
      {:ok, pid} ->
        Process.unlink(pid)
        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        {:error, :repo_already_started_without_known_application_name}

      {:error, _} = error ->
        error
    end
  end

  defp teardown(repo_pid) do
    try do
      Ecto.Adapters.SQL.query(@repo, @ddl_drop, [])
    catch
      _, _ -> :ok
    end

    if Process.alive?(repo_pid) do
      ref = Process.monitor(repo_pid)
      Process.exit(repo_pid, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^repo_pid, _} -> :ok
      after
        5_000 -> :ok
      end
    end

    :ok
  end

  defp seed!(rows, digest_rows) do
    per_load = max(div(rows - digest_rows, length(@tenants) - 1), 10)

    for tenant <- @tenants, into: %{} do
      inputs =
        if tenant == @digest_tenant do
          for i <- 1..digest_rows, do: %{pid: "p#{i}", name: "Person #{i}", age: i}
        else
          for i <- 1..per_load, do: %{pid: "#{tenant}-p#{i}", name: "#{tenant} Person #{i}", age: i}
        end

      %Ash.BulkResult{status: :success} =
        Ash.bulk_create(inputs, @resource, :create,
          domain: @domain,
          tenant: tenant,
          authorize?: false,
          batch_size: 1_000,
          return_errors?: true,
          stop_on_error?: true
        )

      {tenant, length(inputs)}
    end
  end

  # ---- query helpers ----

  defp base_opts(tenant), do: [domain: @domain, tenant: tenant, actor: %{tenant: tenant}]

  defp refused_code(result) do
    code = Common.code_of(result)

    if is_atom(code) and not is_nil(code) and String.starts_with?(Atom.to_string(code), "REFUSED_"),
      do: code,
      else: nil
  end

  defp owned?(subject, tenant) when is_binary(subject) do
    case String.replace_prefix(subject, @prefix, "") do
      ^subject -> false
      "p" <> rest when tenant == @digest_tenant -> digits?(rest)
      rest -> String.starts_with?(rest, tenant <> "-p")
    end
  end

  defp owned?(_subject, _tenant), do: false

  defp digits?(s), do: s != "" and String.match?(s, ~r/\A\d+\z/)

  # ---- isolated killer scenarios ----

  defp killer_scenario(ctx, query_opts, codes) do
    result = OBDA.query(ctx.specs, @sparql, base_opts(@digest_tenant) ++ query_opts)
    code = Common.code_of(result)

    cond do
      code in codes -> healthy_after(ctx)
      true -> {:fail, {:unexpected, expected: codes, got: code, result: inspect(result, limit: 5)}}
    end
  end

  # The killer must not poison the layer: a healthy query right after is exact.
  defp healthy_after(ctx) do
    case healthy_op(ctx, @digest_tenant) do
      :ok -> :ok
      other -> {:fail, {:unhealthy_after_killer, other}}
    end
  end

  defp fail_closed(ctx) do
    probes = [
      wrong_actor: [domain: @domain, tenant: @digest_tenant, actor: %{tenant: "t1"}],
      nil_actor: [domain: @domain, tenant: @digest_tenant, actor: nil],
      no_tenant: [domain: @domain, actor: %{tenant: @digest_tenant}]
    ]

    leaks =
      for {name, opts} <- probes,
          {:ok, %{bindings: [_ | _] = rows}} <- [OBDA.query(ctx.specs, @sparql, opts)],
          do: {name, length(rows)}

    if leaks == [], do: :ok, else: {:fail, {:rows_published_without_admission, leaks}}
  end

  # ---- healthy / killer ops ----

  defp healthy_op(ctx, tenant) do
    case OBDA.query(ctx.specs, @sparql, base_opts(tenant) ++ [timeout_ms: 60_000]) do
      {:ok, %{bindings: rows}} ->
        expected = Map.fetch!(ctx.counts, tenant)
        leaked = Enum.reject(rows, &owned?(&1["s"], tenant))

        cond do
          leaked != [] -> {:leak, tenant, length(leaked), Enum.take(leaked, 2)}
          length(rows) != expected -> {:bad, {:row_count, tenant, length(rows), expected}}
          true -> :ok
        end

      other ->
        case refused_code(other) do
          nil -> {:bad, {:untyped, inspect(other, limit: 5)}}
          code -> {:typed, code}
        end
    end
  end

  defp killer_op(ctx, tenant, i) do
    {query_opts, _codes} = @killers_isolated |> Enum.at(rem(i, length(@killers_isolated))) |> elem(1)
    result = OBDA.query(ctx.specs, @sparql, base_opts(tenant) ++ query_opts)

    case result do
      {:ok, %{bindings: rows}} ->
        {:bad, {:killer_not_refused, tenant, length(rows)}}

      other ->
        case refused_code(other) do
          nil -> {:bad, {:untyped, inspect(other, limit: 5)}}
          _code -> :ok
        end
    end
  end

  # ---- storm ----

  defp storm(ctx, callers, killers, check_pg? \\ false) do
    outcomes =
      run_callers(callers, fn n ->
        tenant = Enum.at(@tenants, rem(n, length(@tenants)))
        role = if n < killers, do: :killer, else: :healthy

        for j <- 1..@calls_each do
          safe(fn ->
            if role == :killer, do: killer_op(ctx, tenant, n + j), else: healthy_op(ctx, tenant)
          end)
        end
        |> Enum.map(&{role, &1})
      end)

    {crashed, finished} = Enum.split_with(outcomes, &(elem(&1, 0) != :ok))
    flat = finished |> Enum.flat_map(&elem(&1, 1))

    leaks = for {_, {:leak, _, _, _} = l} <- flat, do: l
    bad = for {_, {:bad, _} = b} <- flat, do: b
    healthy_ok = Enum.count(flat, &match?({:healthy, :ok}, &1))
    killer_ok = Enum.count(flat, &match?({:killer, :ok}, &1))
    typed = for {:healthy, {:typed, code}} <- flat, do: code

    IO.puts(
      "    storm callers=#{callers}: healthy_ok=#{healthy_ok} killer_ok=#{killer_ok} " <>
        "typed_healthy_refusals=#{inspect(Enum.frequencies(typed))} crashed=#{length(crashed)}"
    )

    cond do
      leaks != [] -> {:fail, {:cross_tenant_leak, Enum.take(leaks, 3)}}
      bad != [] -> {:fail, {:bad_outcomes, length(bad), Enum.take(bad, 3)}}
      crashed != [] -> {:fail, {:caller_crashes, inspect(crashed, limit: 3)}}
      healthy_ok == 0 -> {:fail, :no_healthy_call_succeeded}
      killer_ok == 0 -> {:fail, :no_killer_refused}
      check_pg? -> await_idle(ctx, 15_000)
      true -> :ok
    end
  end

  defp run_callers(count, fun) do
    {:ok, sup} = Task.Supervisor.start_link()

    results =
      sup
      |> Task.Supervisor.async_stream_nolink(0..(count - 1), fun,
        max_concurrency: count,
        timeout: 180_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.to_list()

    Supervisor.stop(sup)
    results
  end

  defp safe(fun) do
    fun.()
  catch
    kind, reason -> {:bad, {:raised, kind, inspect(reason, limit: 5)}}
  end

  # ---- pg_stat_activity: no non-idle query from this app after worker kills ----

  @activity_sql "SELECT count(*) FROM pg_stat_activity " <>
                  "WHERE application_name = $1 AND state <> 'idle' AND pid <> pg_backend_pid()"

  defp await_idle(ctx, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    poll_idle(ctx, deadline)
  end

  defp poll_idle(ctx, deadline) do
    %{rows: [[active]]} = Ecto.Adapters.SQL.query!(@repo, @activity_sql, [ctx.app_name])

    cond do
      active == 0 ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:fail, {:non_idle_queries_after_kills, active, app: ctx.app_name}}

      true ->
        # SLEEP-CLASS: POLL-STEP
        receive do
        after
          25 -> :ok
        end

        poll_idle(ctx, deadline)
    end
  end
end
