# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer `ets` (Ash.DataLayer.Ets). Implements the Bench.Layer contract:
#
#   available?/0, setup/1, scenarios/0, canonical_digest/1
#
# Scenarios (each returns :ok | {:fail, why}):
#   s1_heap_bomb      10k rows x 8KB under max_heap_words -> REFUSED_MEMORY_LIMIT_EXCEEDED,
#                     caller alive, memory back to baseline
#   s2_row_bound      50k rows, max_rows 1_000 -> REFUSED_RESULT_LIMIT_EXCEEDED within 100 ms
#   s3_triple_fanout  30 non-nil predicates x 5000 rows, max_triples 25_000 ->
#                     REFUSED_TRIPLE_LIMIT_EXCEEDED (budget 200 ms: ETS casts the whole table)
#   s4_timeout        500 ms manual read, timeout_ms 50 -> REFUSED_QUERY_TIMEOUT in 50..150 ms,
#                     process count settles to baseline (bounded deadline poll)
#   s5_storm          64 callers (32 killers / 32 healthy) for opts[:seconds] (default 60)
#   s6_soak           10k unique queries; atom/ETS/process/memory leak deltas
#
# Requires Bench.Layer.Common.code_of/1 (lane `common`) to be loaded before scenarios run.

defmodule Bench.Layer.Ets.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Bench.Layer.Ets.Person
    resource Bench.Layer.Ets.DigestPerson
    resource Bench.Layer.Ets.Blob
    resource Bench.Layer.Ets.Row
  end
end

defmodule Bench.Layer.Ets.Person do
  use Ash.Resource, domain: Bench.Layer.Ets.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pid, :name, :age]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :pid, :string, public?: true
    attribute :name, :string, public?: true
    attribute :age, :integer, public?: true
  end
end

defmodule Bench.Layer.Ets.DigestPerson do
  use Ash.Resource, domain: Bench.Layer.Ets.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pid, :name, :age]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :pid, :string, public?: true
    attribute :name, :string, public?: true
    attribute :age, :integer, public?: true
  end
end

defmodule Bench.Layer.Ets.Blob do
  use Ash.Resource, domain: Bench.Layer.Ets.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:payload]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :payload, :string, public?: true
  end
end

defmodule Bench.Layer.Ets.Row do
  use Ash.Resource, domain: Bench.Layer.Ets.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:label]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true
  end
end

defmodule Bench.Layer.Ets do
  alias AshR2RML.Mapping.{
    Datatype,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.{Result, Worker}
  alias Bench.Layer.Ets.{Blob, DigestPerson, Dom, Person, Row}

  @ex "https://ex.org/"
  @name "https://schema.org/name"
  @age "https://schema.org/age"
  @xsd "http://www.w3.org/2001/XMLSchema#"
  @shared_sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"

  @default_rows 10_000
  @default_digest_rows 500
  @default_seconds 60

  @blob_rows 10_000
  @blob_bytes 8 * 1024
  @heap_words 2_000_000
  @memory_slack_bytes 32 * 1024 * 1024
  @row_rows 50_000
  @row_limit 1_000
  @s2_budget_ms 100
  @wide_predicates 30
  @wide_rows 5_000
  @s3_budget_ms 200
  @s4_timeout_ms 50
  @s4_upper_ms 150
  @settle_deadline_ms 2_000

  @callers 64
  @killers 32
  @killer_kinds 6
  @digest_re ~r/\A[0-9a-f]{64}\z/

  @soak_total 10_000
  @soak_warmup 500
  @soak_every 1_000
  @soak_atom_budget 5
  @soak_mem_drift 0.05
  @soak_settle_ms 5_000

  # -- contract ---------------------------------------------------------------

  def available? do
    if Code.ensure_loaded?(Ash.DataLayer.Ets) do
      :ok
    else
      {:skip, "Ash.DataLayer.Ets not loadable"}
    end
  end

  def setup(opts) do
    case available?() do
      :ok ->
        {:ok, _} = Application.ensure_all_started(:ash)
        rows = Keyword.get(opts, :rows, @default_rows)
        digest_rows = Keyword.get(opts, :digest_rows, @default_digest_rows)

        reset!(Person)
        reset!(DigestPerson)
        seed_people!(Person, rows)
        seed_people!(DigestPerson, digest_rows)

        {:ok,
         %{
           specs: [{Person, person_mapping(Person)}],
           digest_specs: [{DigestPerson, person_mapping(DigestPerson)}],
           domain: Dom,
           resource: Person,
           seed_rows: rows,
           digest_rows: digest_rows,
           seconds: Keyword.get(opts, :seconds, @default_seconds),
           teardown: fn -> teardown() end
         }}

      {:skip, _} = skip ->
        skip
    end
  end

  def scenarios do
    [
      {:s1_heap_bomb, "10k x 8KB rows under max_heap_words refuse memory limit", &s1/1},
      {:s2_row_bound, "50k rows with max_rows 1_000 refuse within 100 ms", &s2/1},
      {:s3_triple_fanout, "30 predicates x 5000 rows, max_triples 25_000 refuse", &s3/1},
      {:s4_timeout, "500 ms read with timeout_ms 50 refuses; processes settle", &s4/1},
      {:s5_storm, "64-way killer/healthy storm, typed refusals and exact answers", &s5/1},
      {:s6_soak, "10k unique queries, no atom/ETS/process/memory leak", &s6/1}
    ]
  end

  def canonical_digest(ctx) do
    case OBDA.query(ctx.digest_specs, @shared_sparql,
           domain: ctx.domain,
           max_rows: max(ctx.digest_rows * 2, 1_000)
         ) do
      {:ok, %Result{} = result} ->
        Bench.Layer.Common.digest_of(result)

      other ->
        raise "ets canonical_digest: query did not return {:ok, %Result{}}: " <>
                inspect(other, limit: 5)
    end
  end

  # -- S1 ---------------------------------------------------------------------

  defp s1(_ctx) do
    reset!(Blob)

    seed!(Blob, :payload, @blob_rows, fn i ->
      String.duplicate(<<rem(i, 26) + 97>>, @blob_bytes)
    end)

    gc_all()
    baseline = :erlang.memory(:total)
    caller = self()

    outcome =
      OBDA.query(
        [{Blob, blob_mapping()}],
        "SELECT ?s ?p WHERE { ?s <#{@ex}payload> ?p }",
        domain: Dom,
        max_heap_words: @heap_words,
        timeout_ms: 60_000,
        max_rows: @blob_rows * 2
      )

    gc_all()
    delta = :erlang.memory(:total) - baseline
    reset!(Blob)

    cond do
      code(outcome) != :REFUSED_MEMORY_LIMIT_EXCEEDED ->
        {:fail, "expected REFUSED_MEMORY_LIMIT_EXCEEDED, got #{inspect(outcome, limit: 5)}"}

      not Process.alive?(caller) ->
        {:fail, "caller died"}

      delta > @memory_slack_bytes ->
        {:fail, "memory not back to baseline: +#{delta} bytes (slack #{@memory_slack_bytes})"}

      true ->
        :ok
    end
  end

  # -- S2 ---------------------------------------------------------------------

  defp s2(_ctx) do
    reset!(Row)
    seed!(Row, :label, @row_rows, fn i -> "row-#{i}" end)
    gc_all()

    {us, outcome} =
      :timer.tc(fn ->
        OBDA.query(
          [{Row, row_mapping()}],
          "SELECT ?s ?l WHERE { ?s <#{@ex}label> ?l }",
          domain: Dom,
          max_rows: @row_limit
        )
      end)

    ms = us / 1000
    text = inspect(outcome, limit: :infinity, printable_limit: :infinity)
    reset!(Row)

    cond do
      code(outcome) != :REFUSED_RESULT_LIMIT_EXCEEDED ->
        {:fail, "expected REFUSED_RESULT_LIMIT_EXCEEDED, got #{inspect(outcome, limit: 5)}"}

      ms > @s2_budget_ms ->
        {:fail, "refusal took #{Float.round(ms, 1)} ms (budget #{@s2_budget_ms})"}

      not String.contains?(text, Integer.to_string(@row_limit)) ->
        {:fail, "refusal does not name the limit #{@row_limit}: #{text}"}

      true ->
        :ok
    end
  end

  # -- S3 ---------------------------------------------------------------------

  defp s3(_ctx) do
    names = for i <- 1..@wide_predicates, do: :"p#{i}"
    domain = Module.concat(__MODULE__, WideDomain)
    resource = Module.concat(__MODULE__, Wide)
    ensure_wide!(domain, resource, names)

    reset!(resource)

    inputs =
      for r <- 1..@wide_rows do
        Map.new(names, fn n -> {n, "v#{r}-#{n}"} end)
      end

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(inputs, resource, :create,
        domain: domain,
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )

    {us, outcome} =
      :timer.tc(fn ->
        OBDA.query([resource], "SELECT ?s ?o WHERE { ?s <#{@ex}bench/p1> ?o . }",
          domain: domain,
          max_triples: 25_000
        )
      end)

    ms = us / 1000
    reset!(resource)

    cond do
      code(outcome) != :REFUSED_TRIPLE_LIMIT_EXCEEDED ->
        {:fail, "expected REFUSED_TRIPLE_LIMIT_EXCEEDED, got #{inspect(outcome, limit: 5)}"}

      ms > @s3_budget_ms ->
        {:fail, "refusal took #{Float.round(ms, 1)} ms (budget #{@s3_budget_ms})"}

      true ->
        :ok
    end
  end

  defp ensure_wide!(domain, resource, names) do
    unless Code.ensure_loaded?(resource) do
      attr_asts =
        for n <- names do
          quote do
            attribute unquote(n), :string, allow_nil?: false, public?: true
          end
        end

      mappings = for n <- names, do: {n, "#{@ex}bench/#{n}"}

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
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshR2RML]

          ets do
            private? true
          end

          r2rml do
            class_iri("https://ex.org/bench/Wide")
            subject_template("https://ex.org/bench/Wide/{id}")
            table_name("bench_wide")
            attribute_mappings(unquote(Macro.escape(mappings)))
          end

          actions do
            defaults [:read]

            create :create do
              primary? true
              accept unquote(names)
            end
          end

          attributes do
            uuid_primary_key :id
            unquote_splicing(attr_asts)
          end
        end,
        Macro.Env.location(__ENV__)
      )
    end

    :ok
  end

  # -- S4 ---------------------------------------------------------------------

  defp s4(_ctx) do
    domain = Module.concat(__MODULE__, SlowDomain)
    reader = Module.concat(__MODULE__, SlowRead)
    resource = Module.concat(__MODULE__, SlowResource)
    ensure_slow!(domain, reader, resource)

    sparql = "SELECT ?s ?name WHERE { ?s <#{@ex}bench/name> ?name . }"
    baseline = :erlang.system_info(:process_count)

    {us, outcome} =
      :timer.tc(fn ->
        OBDA.query([resource], sparql, domain: domain, timeout_ms: @s4_timeout_ms)
      end)

    ms = us / 1000
    {settled?, final, waited_ms} = settle_processes(baseline)

    cond do
      code(outcome) != :REFUSED_QUERY_TIMEOUT ->
        {:fail, "expected REFUSED_QUERY_TIMEOUT, got #{inspect(outcome, limit: 5)}"}

      ms < @s4_timeout_ms or ms > @s4_upper_ms ->
        {:fail,
         "refused in #{Float.round(ms, 1)} ms (window #{@s4_timeout_ms}-#{@s4_upper_ms} ms)"}

      not settled? ->
        {:fail,
         "process_count #{baseline} -> #{final} not settled after #{waited_ms} ms deadline"}

      true ->
        :ok
    end
  end

  defp ensure_slow!(domain, reader, resource) do
    unless Code.ensure_loaded?(resource) do
      Module.create(
        reader,
        quote do
          use Ash.Resource.ManualRead

          # A real slow data source: the read genuinely blocks 500 ms (the stressor, not a
          # synchronization step). Expressed as a receive timeout.
          @impl true
          def read(_ash_query, _data_layer_query, _opts, _context) do
            receive do
            after
              500 -> {:ok, []}
            end
          end
        end,
        Macro.Env.location(__ENV__)
      )

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
            data_layer: Ash.DataLayer.Ets,
            extensions: [AshR2RML]

          ets do
            private? true
          end

          r2rml do
            class_iri("https://ex.org/bench/Slow")
            subject_template("https://ex.org/bench/Slow/{id}")
            table_name("bench_slow")
            attribute_mappings([{:name, "https://ex.org/bench/name"}])
          end

          actions do
            read :read do
              primary? true
              manual unquote(reader)
            end
          end

          attributes do
            uuid_primary_key :id
            attribute :name, :string, public?: true
          end
        end,
        Macro.Env.location(__ENV__)
      )
    end

    :ok
  end

  # Bounded deadline poll on the observable (process_count).
  defp settle_processes(baseline) do
    started = System.monotonic_time(:millisecond)
    poll_processes(baseline, started, started + @settle_deadline_ms)
  end

  defp poll_processes(baseline, started, deadline) do
    count = :erlang.system_info(:process_count)
    now = System.monotonic_time(:millisecond)

    cond do
      count <= baseline -> {true, count, now - started}
      now >= deadline -> {false, count, now - started}
      true -> poll_processes(baseline, started, deadline)
    end
  end

  # -- S5 ---------------------------------------------------------------------

  defp s5(ctx) do
    seconds = Map.get(ctx, :seconds, @default_seconds)
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    {:ok, sup} = Task.Supervisor.start_link()
    persons = min(ctx.seed_rows, 100)

    results =
      sup
      |> Task.Supervisor.async_stream_nolink(
        0..(@callers - 1),
        fn n -> caller(ctx, persons, n, deadline) end,
        max_concurrency: @callers,
        timeout: seconds * 1000 + 120_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.to_list()

    {crashed, finished} = Enum.split_with(results, &(elem(&1, 0) != :ok))
    reports = Enum.map(finished, &elem(&1, 1))

    per_role =
      for role <- [:killer, :healthy] do
        rs = Enum.filter(reports, &(&1.role == role))

        {role, Enum.sum(Enum.map(rs, & &1.calls)), Enum.sum(Enum.map(rs, & &1.bad)),
         rs |> Enum.flat_map(& &1.samples) |> Enum.take(3)}
      end

    failures =
      Enum.flat_map(per_role, fn {role, calls, bad, samples} ->
        cond do
          calls == 0 -> ["#{role}: zero calls completed"]
          bad > 0 -> ["#{role}: #{bad}/#{calls} bad, samples #{inspect(samples)}"]
          true -> []
        end
      end)

    failures =
      if crashed == [],
        do: failures,
        else: ["caller crashes/timeouts: #{inspect(crashed, limit: 5)}" | failures]

    Supervisor.stop(sup)
    if failures == [], do: :ok, else: {:fail, Enum.join(failures, "; ")}
  end

  defp caller(ctx, persons, n, deadline) do
    role = if n < @killers, do: :killer, else: :healthy
    op = if role == :killer, do: &killer_op(ctx, &1), else: &healthy_op(ctx, persons, &1)
    storm_loop(role, op, n, deadline, %{role: role, calls: 0, bad: 0, samples: []})
  end

  defp storm_loop(role, op, i, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      acc =
        case safe(op, i) do
          :ok ->
            %{acc | calls: acc.calls + 1}

          {:bad, reason} ->
            %{
              acc
              | calls: acc.calls + 1,
                bad: acc.bad + 1,
                samples: Enum.take([reason | acc.samples], 3)
            }
        end

      storm_loop(role, op, i + 1, deadline, acc)
    end
  end

  defp safe(op, i) do
    op.(i)
  catch
    kind, reason -> {:bad, {:raised, kind, inspect(reason)}}
  end

  defp point_sparql(k), do: "SELECT ?n WHERE { <#{@ex}person/p#{k}> <#{@name}> ?n }"

  defp healthy_op(ctx, persons, i) do
    k = rem(i, persons) + 1
    expected = [%{"n" => "Person #{k}"}]

    case OBDA.query(ctx.specs, point_sparql(k), domain: ctx.domain, timeout_ms: 30_000) do
      {:ok, %Result{bindings: ^expected, digest: digest}} when is_binary(digest) ->
        if Regex.match?(@digest_re, digest), do: :ok, else: {:bad, {:digest, digest}}

      other ->
        {:bad, {:point, summarize(other)}}
    end
  end

  defp killer_op(ctx, i) do
    sparql = point_sparql(1)
    kind = rem(i, @killer_kinds)

    result =
      case kind do
        0 ->
          OBDA.query([], sparql)

        1 ->
          OBDA.query(ctx.specs, sparql, domain: ctx.domain, max_triples: 1)

        2 ->
          OBDA.query(ctx.specs, "SELECT ?n WHERE { ?s <#{@name}> ?n }",
            domain: ctx.domain,
            max_rows: 1
          )

        3 ->
          OBDA.query(ctx.specs, sparql, domain: ctx.domain, authorize?: false)

        4 ->
          OBDA.query(ctx.specs, @shared_sparql, domain: ctx.domain, max_heap_words: 2_000)

        5 ->
          Worker.run(
            fn ->
              receive do
                :never -> :ok
              end
            end,
            timeout_ms: 20
          )
      end

    case Bench.Layer.Common.code_of(result) do
      code when is_atom(code) and not is_nil(code) ->
        if String.starts_with?(Atom.to_string(code), "REFUSED_"),
          do: :ok,
          else: {:bad, {:code, kind, code}}

      _ ->
        {:bad, {:kind, kind, summarize(result)}}
    end
  end

  defp summarize({:ok, %Result{digest: d, bindings: b}}), do: {:ok, d, length(b)}
  defp summarize({:error, %{code: code}}), do: {:error, code}
  defp summarize(other), do: other

  # -- S6 ---------------------------------------------------------------------

  defp s6(ctx) do
    # Preflight: the query shape must be answerable, otherwise the soak measures refusals.
    case soak_one(ctx, 0) do
      {:ok, _} -> soak_run(ctx)
      {:fail, _} = fail -> fail
    end
  end

  defp soak_run(ctx) do
    with :ok <- soak_range(ctx, Enum.map(1..@soak_warmup, &(-&1))) do
      settle_gc()
      base = snapshot(:baseline)
      IO.puts("  " <> format_snapshot(base))

      case soak_loop(ctx, 1, base) do
        :ok ->
          settle_gc()
          final = snapshot(:final)
          IO.puts("  " <> format_snapshot(final))

          case soak_breaches(base, final) do
            [] -> :ok
            breaches -> {:fail, Enum.join(breaches, "; ")}
          end

        {:fail, _} = fail ->
          fail
      end
    end
  end

  defp soak_range(_ctx, []), do: :ok

  defp soak_range(ctx, [n | rest]) do
    case soak_one(ctx, n) do
      {:ok, _} -> soak_range(ctx, rest)
      {:fail, _} = fail -> fail
    end
  end

  defp soak_loop(_ctx, n, _base) when n > @soak_total, do: :ok

  defp soak_loop(ctx, n, base) do
    case soak_one(ctx, n) do
      {:ok, _} ->
        if rem(n, @soak_every) == 0, do: IO.puts("  " <> format_snapshot(snapshot(n)))
        soak_loop(ctx, n + 1, base)

      {:fail, _} = fail ->
        fail
    end
  end

  # Unique subject IRI and unique filter string per run; all binaries.
  defp soak_one(ctx, n) do
    k = "u#{n}-#{System.unique_integer([:positive])}"

    sparql = """
    SELECT ?name WHERE {
      <#{@ex}person/#{k}> <#{@name}> ?name .
      FILTER(?name = "#{k}")
    }
    """

    case OBDA.query(ctx.specs, sparql, domain: ctx.domain) do
      {:ok, _} = ok -> ok
      other -> {:fail, "soak query #{n} did not return {:ok, _}: #{inspect(other, limit: 5)}"}
    end
  end

  defp snapshot(label) do
    %{
      label: label,
      memory: :erlang.memory(:total),
      atoms: :erlang.system_info(:atom_count),
      ets: length(:ets.all()),
      procs: :erlang.system_info(:process_count)
    }
  end

  defp format_snapshot(s),
    do: "snapshot #{s.label}: memory=#{s.memory} atoms=#{s.atoms} ets=#{s.ets} procs=#{s.procs}"

  # Full GC, then bounded deadline poll until the process count stops moving.
  defp settle_gc do
    settle_gc(System.monotonic_time(:millisecond) + @soak_settle_ms, -1)
  end

  defp settle_gc(deadline, last) do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    now = :erlang.system_info(:process_count)

    cond do
      now == last ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :ok

      true ->
        # SLEEP-CLASS: POLL-STEP (bounded by deadline; lets exiting processes finish)
        receive do
        after
          25 -> :ok
        end

        settle_gc(deadline, now)
    end
  end

  defp soak_breaches(base, final) do
    drift = abs(final.memory - base.memory) / base.memory

    [
      {final.atoms - base.atoms > @soak_atom_budget,
       "atom delta #{final.atoms - base.atoms} > #{@soak_atom_budget}"},
      {final.ets != base.ets, "ETS tables #{base.ets} -> #{final.ets}"},
      {final.procs != base.procs, "processes #{base.procs} -> #{final.procs}"},
      {drift > @soak_mem_drift,
       "post-GC memory drift #{Float.round(drift * 100, 2)}% > #{@soak_mem_drift * 100}%"}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  # -- mappings ---------------------------------------------------------------

  defp person_mapping(resource) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: "person"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "person/{pid}"},
      class_iris: [@ex <> "Person"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name,
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: :string, rdf_datatype: @xsd <> "string"}
          }
        },
        %PredicateObjectMap{
          attribute: :age,
          predicate_iri: @age,
          object_map: %ObjectMap{
            strategy: :column,
            value: "age",
            datatype: %Datatype{ash_type: :integer, rdf_datatype: @xsd <> "integer"}
          }
        }
      ]
    }
  end

  defp blob_mapping do
    %Resource{
      ash_resource: Blob,
      logical_table: %LogicalTable{table_name: "blob"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "blob/{id}"},
      class_iris: [@ex <> "Blob"],
      identities: [[:id]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :payload,
          predicate_iri: @ex <> "payload",
          object_map: %ObjectMap{strategy: :column, value: "payload"}
        }
      ]
    }
  end

  defp row_mapping do
    %Resource{
      ash_resource: Row,
      logical_table: %LogicalTable{table_name: "row"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "row/{id}"},
      class_iris: [@ex <> "Row"],
      identities: [[:id]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :label,
          predicate_iri: @ex <> "label",
          object_map: %ObjectMap{strategy: :column, value: "label"}
        }
      ]
    }
  end

  # -- helpers ----------------------------------------------------------------

  defp code(outcome), do: Bench.Layer.Common.code_of(outcome)

  defp seed_people!(resource, n) do
    inputs = for i <- 1..n//1, do: %{pid: "p#{i}", name: "Person #{i}", age: i}
    bulk!(resource, inputs)
  end

  defp seed!(resource, field, count, value_fun) do
    bulk!(resource, for(i <- 1..count, do: %{field => value_fun.(i)}))
  end

  defp bulk!(_resource, []), do: :ok

  defp bulk!(resource, inputs) do
    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(inputs, resource, :create,
        domain: Dom,
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )

    :ok
  end

  defp reset!(resource) do
    Ash.DataLayer.Ets.stop(resource)
    :ok
  end

  defp teardown do
    Enum.each([Person, DigestPerson, Blob, Row], &Ash.DataLayer.Ets.stop/1)

    for suffix <- [Wide, SlowResource],
        mod = Module.concat(__MODULE__, suffix),
        Code.ensure_loaded?(mod),
        do: Ash.DataLayer.Ets.stop(mod)

    :ok
  end

  defp gc_all do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    :erlang.garbage_collect()
  end
end
