# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer `simple`: Ash.DataLayer.Simple resources whose only read path is a manual read
# action. Simple has no query surface, so the manual read ignores every pushdown (filter, sort,
# limit); the OBDA envelope must enforce the bounds itself and fail closed.
#
# Module contract: Bench.Layer.Simple implements available?/0, setup/1, scenarios/0 and
# canonical_digest/1 (see the layer lane contract). Resources are generated per scenario with
# Module.create; their behavior (row count, raise, sleep) lives in :persistent_term keyed by the
# resource module, read by the shared manual read in the worker process.
#
# Table name "bench_person" and the shared healthy mapping are intentionally identical across
# layers so the canonical digest (which covers the rendered R2RML) can match.

defmodule Bench.Layer.Simple.Read do
  @moduledoc false
  use Ash.Resource.ManualRead

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    resource = query.resource
    cfg = :persistent_term.get({Bench.Layer.Simple, :cfg, resource})

    case :persistent_term.get({Bench.Layer.Simple, :observer, resource}, nil) do
      pid when is_pid(pid) -> send(pid, {:simple_read_pid, resource, self()})
      _ -> :ok
    end

    case cfg.mode do
      :raise ->
        raise "bench simple layer: manual read raised on purpose"

      :sleep ->
        # The wait IS the stressor (a real slow source), not synchronization: it is killed by the
        # OBDA worker timeout.
        receive do
        after
          cfg.sleep_ms -> :ok
        end

        {:ok, rows(resource, cfg.count)}

      :rows ->
        {:ok, rows(resource, cfg.count)}
    end
  end

  defp rows(_resource, 0), do: []

  defp rows(resource, count) do
    for i <- 1..count do
      struct(resource, pid: "p#{i}", name: "Person #{i}", age: i)
    end
  end
end

defmodule Bench.Layer.Simple do
  @moduledoc false

  alias AshR2RML.OBDA

  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @poll_deadline_ms 2_000

  # -- contract ---------------------------------------------------------------

  def available? do
    if Code.ensure_loaded?(Ash.DataLayer.Simple) and Code.ensure_loaded?(AshR2RML.OBDA),
      do: :ok,
      else: {:skip, "Ash.DataLayer.Simple or AshR2RML.OBDA not loadable"}
  end

  def setup(opts) do
    case available?() do
      :ok ->
        rows = Keyword.get(opts, :rows, 10_000)
        digest_rows = Keyword.get(opts, :digest_rows, 500)

        {resource, mapping, domain} = build(%{mode: :rows, count: rows, sleep_ms: 0})
        {dres, dmapping, _ddomain} = build(%{mode: :rows, count: digest_rows, sleep_ms: 0})

        {:ok,
         %{
           specs: [{resource, mapping}],
           domain: domain,
           resource: resource,
           seed_rows: rows,
           digest_specs: [{dres, dmapping}],
           digest_rows: digest_rows,
           teardown: &teardown/0
         }}

      skip ->
        skip
    end
  end

  def scenarios do
    [
      {:s1_heap, "row-heavy read under a tiny max_heap_words -> REFUSED_MEMORY_LIMIT_EXCEEDED, worker dead",
       &s1_heap/1},
      {:s2_rows, "5k rows from a pushdown-ignoring read, max_rows 1000 -> REFUSED_RESULT_LIMIT_EXCEEDED",
       &s2_rows/1},
      {:s3_triples, "5k rows, max_triples 1000 -> REFUSED_TRIPLE_LIMIT_EXCEEDED", &s3_triples/1},
      {:s4_timeout, "slow read, timeout 50 ms -> REFUSED_QUERY_TIMEOUT before the read could finish", &s4_timeout/1},
      {:s5_burst, "concurrent healthy + killer callers: healthy digests identical, killers typed refusals",
       &s5_burst/1},
      {:s9a_manual_50k, "manual read returns 50k structs, default bounds -> REFUSED_RESULT_LIMIT_EXCEEDED",
       &s9a_manual_50k/1},
      {:s9b_manual_raise, "manual read raises -> typed error, no exception escapes OBDA.query", &s9b_manual_raise/1},
      {:s9c_manual_sleep, "manual read sleeps past timeout_ms -> REFUSED_QUERY_TIMEOUT, 0 leaked processes",
       &s9c_manual_sleep/1}
    ]
  end

  def canonical_digest(ctx) do
    case OBDA.query(ctx.digest_specs, @sparql, domain: ctx.domain) do
      {:ok, %AshR2RML.OBDA.Result{} = result} ->
        Bench.Layer.Common.digest_of(result)

      other ->
        raise "simple layer canonical_digest failed: #{inspect(other, limit: 5)}"
    end
  end

  # -- scenarios --------------------------------------------------------------

  defp s1_heap(_ctx) do
    {resource, mapping, _d} = build(%{mode: :rows, count: 20_000, sleep_ms: 0})

    with {:ok, pid_ref} <- observe(resource),
         result = run([{resource, mapping}], max_rows: 100_000, max_triples: 10_000_000, max_heap_words: 100_000),
         :ok <- expect_code(result, :REFUSED_MEMORY_LIMIT_EXCEEDED) do
      await_dead(pid_ref, resource)
    end
  end

  defp s2_rows(_ctx) do
    {resource, mapping, _d} = build(%{mode: :rows, count: 5_000, sleep_ms: 0})
    expect_code(run([{resource, mapping}], max_rows: 1_000), :REFUSED_RESULT_LIMIT_EXCEEDED)
  end

  defp s3_triples(_ctx) do
    {resource, mapping, _d} = build(%{mode: :rows, count: 5_000, sleep_ms: 0})
    expect_code(run([{resource, mapping}], max_triples: 1_000), :REFUSED_TRIPLE_LIMIT_EXCEEDED)
  end

  # The read sleeps 1000 ms; a refusal before 500 ms proves the timeout cut the read short
  # (ratio against the read's own duration, not an absolute load-bound bound).
  defp s4_timeout(_ctx) do
    {resource, mapping, _d} = build(%{mode: :sleep, count: 3, sleep_ms: 1_000})

    started = System.monotonic_time(:millisecond)
    result = run([{resource, mapping}], timeout_ms: 50)
    elapsed = System.monotonic_time(:millisecond) - started

    with :ok <- expect_code(result, :REFUSED_QUERY_TIMEOUT) do
      if elapsed < 500, do: :ok, else: {:fail, {:timeout_not_enforced_promptly, elapsed_ms: elapsed}}
    end
  end

  defp s5_burst(ctx) do
    {killer, kmapping, _d} = build(%{mode: :rows, count: 5_000, sleep_ms: 0})
    expected = canonical_digest(ctx)

    jobs = for i <- 1..16, do: if(rem(i, 2) == 0, do: :healthy, else: :killer)

    outcomes =
      jobs
      |> Task.async_stream(
        fn
          :healthy -> {:healthy, run(ctx.digest_specs, domain: ctx.domain)}
          :killer -> {:killer, run([{killer, kmapping}], max_rows: 100)}
        end,
        max_concurrency: 16,
        timeout: 60_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.to_list()

    bad =
      Enum.flat_map(outcomes, fn
        {:ok, {:healthy, {:ok, %AshR2RML.OBDA.Result{} = r}}} ->
          if Bench.Layer.Common.digest_of(r) == expected, do: [], else: [r.stats]
        {:ok, {:killer, result}} -> if expect_code(result, :REFUSED_RESULT_LIMIT_EXCEEDED) == :ok, do: [], else: [result]
        other -> [other]
      end)

    if bad == [], do: :ok, else: {:fail, {:burst_breaches, Enum.take(bad, 3)}}
  end

  defp s9a_manual_50k(_ctx) do
    {resource, mapping, _d} = build(%{mode: :rows, count: 50_000, sleep_ms: 0})
    expect_code(run([{resource, mapping}], []), :REFUSED_RESULT_LIMIT_EXCEEDED)
  end

  defp s9b_manual_raise(_ctx) do
    {resource, mapping, _d} = build(%{mode: :raise, count: 0, sleep_ms: 0})

    case run([{resource, mapping}], []) do
      {:raised, kind, reason} ->
        {:fail, {:exception_escaped, kind, inspect(reason, limit: 5)}}

      {:error, _} = error ->
        case code_of(error) do
          code when is_atom(code) and not is_nil(code) ->
            if String.starts_with?(Atom.to_string(code), "REFUSED_"),
              do: :ok,
              else: {:fail, {:untyped_error_code, code}}

          other ->
            {:fail, {:error_without_code, other}}
        end

      other ->
        {:fail, {:expected_typed_error, inspect(other, limit: 5)}}
    end
  end

  defp s9c_manual_sleep(_ctx) do
    {resource, mapping, _d} = build(%{mode: :sleep, count: 3, sleep_ms: 3_000})
    {:ok, ref} = observe(resource)
    baseline = :erlang.system_info(:process_count)

    result = run([{resource, mapping}], timeout_ms: 100)

    with :ok <- expect_code(result, :REFUSED_QUERY_TIMEOUT),
         :ok <- await_dead(ref, resource) do
      case poll(fn -> :erlang.system_info(:process_count) <= baseline end) do
        true -> :ok
        false -> {:fail, {:leaked_processes, delta: :erlang.system_info(:process_count) - baseline}}
      end
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp run(specs, opts) do
    OBDA.query(specs, @sparql, opts)
  rescue
    exception -> {:raised, :error, exception}
  catch
    kind, reason -> {:raised, kind, reason}
  end

  defp expect_code({:raised, kind, reason}, want),
    do: {:fail, {:exception_escaped, want, kind, inspect(reason, limit: 5)}}

  defp expect_code(result, want) do
    case result do
      {:error, _} ->
        case code_of(result) do
          ^want -> :ok
          got -> {:fail, {:wrong_code, want: want, got: got}}
        end

      other ->
        {:fail, {:expected_refusal, want, inspect(other, limit: 5)}}
    end
  end

  defp code_of(result) do
    if Code.ensure_loaded?(Bench.Layer.Common) and function_exported?(Bench.Layer.Common, :code_of, 1) do
      apply(Bench.Layer.Common, :code_of, [result])
    else
      case result do
        {:error, %{code: code}} -> code
        %{code: code} -> code
        _ -> nil
      end
    end
  end

  # Registers the calling process as observer of the worker pid that executes the manual read.
  defp observe(resource) do
    :persistent_term.put({__MODULE__, :observer, resource}, self())
    {:ok, make_ref()}
  end

  defp await_dead(_ref, resource) do
    pids = collect_pids(resource, [])

    cond do
      pids == [] ->
        {:fail, {:read_never_ran, resource}}

      poll(fn -> Enum.all?(pids, &(not Process.alive?(&1))) end) ->
        :ok

      true ->
        {:fail, {:worker_still_alive, Enum.filter(pids, &Process.alive?/1)}}
    end
  end

  defp collect_pids(resource, acc) do
    receive do
      {:simple_read_pid, ^resource, pid} -> collect_pids(resource, [pid | acc])
    after
      0 -> acc
    end
  end

  # Bounded poll on an observable with a monotonic deadline.
  defp poll(fun) do
    deadline = System.monotonic_time(:millisecond) + @poll_deadline_ms
    do_poll(fun, deadline)
  end

  defp do_poll(fun, deadline) do
    cond do
      fun.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        # SLEEP-CLASS: POLL-STEP (single audited yield between observations)
        receive do
        after
          5 -> do_poll(fun, deadline)
        end
    end
  end

  defp build(cfg) do
    id = System.unique_integer([:positive])
    resource = Module.concat([Bench.Layer.Simple.Gen, "Person#{id}"])
    domain = Module.concat([Bench.Layer.Simple.Gen, "Domain#{id}"])
    reader = Bench.Layer.Simple.Read

    :persistent_term.put({__MODULE__, :cfg, resource}, cfg)
    register(resource, domain)

    Module.create(
      domain,
      quote do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(resource)
        end
      end,
      Macro.Env.location(__ENV__)
    )

    Module.create(
      resource,
      quote do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: Ash.DataLayer.Simple,
          extensions: [AshR2RML.Resource]

        actions do
          read :read do
            primary? true
            manual unquote(reader)
          end
        end

        attributes do
          attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, allow_nil?: false, public?: true
          attribute :age, :integer, allow_nil?: false, public?: true
        end

        identities do
          identity :by_pid, [:pid]
        end

        r2rml do
          table_name("bench_person")
          class("https://ex.org/Person")
          subject template: "https://ex.org/person/{pid}"
          property :name, "https://schema.org/name", datatype: "http://www.w3.org/2001/XMLSchema#string"
          property :age, "https://schema.org/age", datatype: "http://www.w3.org/2001/XMLSchema#integer"
        end
      end,
      Macro.Env.location(__ENV__)
    )

    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(resource)
    {resource, mapping, domain}
  end

  defp register(resource, domain) do
    key = {__MODULE__, :created}
    :persistent_term.put(key, [{resource, domain} | :persistent_term.get(key, [])])
  end

  defp teardown do
    for {resource, domain} <- :persistent_term.get({__MODULE__, :created}, []) do
      :persistent_term.erase({__MODULE__, :cfg, resource})
      :persistent_term.erase({__MODULE__, :observer, resource})

      for mod <- [resource, domain] do
        :code.purge(mod)
        :code.delete(mod)
      end
    end

    :persistent_term.erase({__MODULE__, :created})
    :ok
  end
end
