# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# S5 storm: 64 concurrent callers for a deadline (default 60 s), 32 killers (every call must
# return a typed REFUSED_* error) and 32 healthy callers (every call must return {:ok, result}
# with a 64-hex digest and the exact expected bindings), then a concurrency sweep printing
# mean latency per level (knee detection output only, never asserted).
#
#     mix run bench/stress/s5_storm.exs [--seconds N] [--sweep-seconds N]
#
# Callers run under a Task.Supervisor via async_stream_nolink, so a crashing caller is reported
# as a failure instead of taking the driver down. Waiting is receive/deadline based, never sleep.

defmodule S5.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource S5.Person
    resource S5.Org
  end
end

defmodule S5.Person do
  use Ash.Resource, domain: S5.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pid, :name, :org_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :pid, :string, public?: true
    attribute :name, :string, public?: true
    attribute :org_id, :string, public?: true
  end
end

defmodule S5.Org do
  use Ash.Resource, domain: S5.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:oid, :oname]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :oid, :string, public?: true
    attribute :oname, :string, public?: true
  end
end

defmodule S5.Storm do
  alias AshR2RML.Mapping.{
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.{Result, Worker}

  @ex "https://ex.org/"
  @name "https://schema.org/name"
  @member "https://schema.org/memberOf"
  @org_name "https://schema.org/legalName"

  @callers 64
  @killers 32
  @persons 8
  @orgs 3
  @digest ~r/\A[0-9a-f]{64}\z/

  def main(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [seconds: :integer, sweep_seconds: :integer])
    seconds = Keyword.get(opts, :seconds, 60)
    sweep_seconds = Keyword.get(opts, :sweep_seconds, 3)

    seed!()
    {:ok, sup} = Task.Supervisor.start_link()

    storm_ok? = storm(sup, seconds)
    sweep(sup, sweep_seconds)

    if storm_ok? do
      IO.puts("S5 STORM: PASS")
    else
      IO.puts("S5 STORM: FAIL")
      System.halt(1)
    end
  end

  # ---- fixtures ----

  defp person_mapping do
    %Resource{
      ash_resource: S5.Person,
      logical_table: %LogicalTable{table_name: "person"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "person/{pid}"},
      class_iris: [@ex <> "Person"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name,
          object_map: %ObjectMap{strategy: :column, value: "name"}
        }
      ],
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :org,
          predicate_iri: @member,
          parent_resource: S5.Org,
          joins: [%JoinCondition{child: "org_id", parent: "oid"}]
        }
      ]
    }
  end

  defp org_mapping do
    %Resource{
      ash_resource: S5.Org,
      logical_table: %LogicalTable{table_name: "org"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "org/{oid}"},
      class_iris: [@ex <> "Org"],
      identities: [[:oid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :oname,
          predicate_iri: @org_name,
          object_map: %ObjectMap{strategy: :column, value: "oname"}
        }
      ]
    }
  end

  defp person_specs, do: [{S5.Person, person_mapping()}, {S5.Org, org_mapping()}]
  defp join_specs, do: [{S5.Person, person_mapping()}, {S5.Org, org_mapping()}]

  defp seed! do
    Ash.DataLayer.Ets.stop(S5.Person)
    Ash.DataLayer.Ets.stop(S5.Org)

    for o <- 0..(@orgs - 1) do
      S5.Org
      |> Ash.Changeset.for_create(:create, %{oid: "o#{o}", oname: "Org#{o}"}, domain: S5.Dom)
      |> Ash.create!(domain: S5.Dom)
    end

    for p <- 0..(@persons - 1) do
      S5.Person
      |> Ash.Changeset.for_create(:create, %{pid: "p#{p}", name: "Name#{p}", org_id: "o#{rem(p, @orgs)}"},
        domain: S5.Dom
      )
      |> Ash.create!(domain: S5.Dom)
    end
  end

  # ---- operations ----

  defp point_sparql(p), do: "SELECT ?n WHERE { <#{@ex}person/p#{p}> <#{@name}> ?n }"

  @join_sparql "SELECT ?pn ?on WHERE { ?p <#{@member}> ?o . ?p <#{@name}> ?pn . ?o <#{@org_name}> ?on }"

  # Returns :ok | {:bad, reason}.
  defp healthy_op(i) do
    if rem(i, 2) == 0, do: point_lookup(rem(i, @persons)), else: join()
  end

  defp point_lookup(p) do
    expected = [%{"n" => "Name#{p}"}]

    case OBDA.query(person_specs(), point_sparql(p), domain: S5.Dom, timeout_ms: 30_000) do
      {:ok, %Result{bindings: ^expected, digest: digest}} -> check_digest(digest)
      other -> {:bad, {:point, summarize(other)}}
    end
  end

  defp join do
    case OBDA.query(join_specs(), @join_sparql, domain: S5.Dom, timeout_ms: 30_000) do
      {:ok, %Result{bindings: rows, digest: digest}} when length(rows) == @persons -> check_digest(digest)
      other -> {:bad, {:join, summarize(other)}}
    end
  end

  defp check_digest(digest) when is_binary(digest) do
    if Regex.match?(@digest, digest), do: :ok, else: {:bad, {:digest, digest}}
  end

  defp check_digest(other), do: {:bad, {:digest, other}}

  # Killer kinds rotate; each must yield a typed REFUSED_* code.
  @killer_kinds 6

  defp killer_op(i) do
    sparql = point_sparql(0)

    result =
      case rem(i, @killer_kinds) do
        # unmapped source
        0 -> OBDA.query([], sparql)
        # materialized graph over the triple bound
        1 -> OBDA.query(person_specs(), sparql, domain: S5.Dom, max_triples: 1)
        # result row bound
        2 -> OBDA.query(person_specs(), "SELECT ?n WHERE { ?s <#{@name}> ?n }", domain: S5.Dom, max_rows: 1)
        # authorization bypass without explicit admission
        3 -> OBDA.query(person_specs(), sparql, domain: S5.Dom, authorize?: false)
        # worker heap cap
        4 -> OBDA.query(person_specs(), @join_sparql, domain: S5.Dom, max_heap_words: 2_000)
        # worker wall-clock cap on a genuinely blocked real worker
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

    case result do
      {:error, %{code: code}} when is_atom(code) ->
        if String.starts_with?(Atom.to_string(code), "REFUSED_"), do: :ok, else: {:bad, {:code, code}}

      other ->
        {:bad, {:kind, rem(i, @killer_kinds), summarize(other)}}
    end
  end

  defp summarize({:ok, %Result{digest: d, bindings: b}}), do: {:ok, d, length(b)}
  defp summarize({:error, %{code: code}}), do: {:error, code}
  defp summarize(other), do: other

  # ---- storm ----

  defp storm(sup, seconds) do
    deadline = System.monotonic_time(:millisecond) + seconds * 1000
    IO.puts("S5 storm: #{@callers} callers (#{@killers} killer / #{@callers - @killers} healthy) for #{seconds}s")

    results =
      sup
      |> Task.Supervisor.async_stream_nolink(0..(@callers - 1), fn n -> caller(n, deadline) end,
        max_concurrency: @callers,
        timeout: seconds * 1000 + 120_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.to_list()

    {crashed, finished} = Enum.split_with(results, &(elem(&1, 0) != :ok))
    reports = Enum.map(finished, &elem(&1, 1))

    summary =
      for role <- [:killer, :healthy] do
        rs = Enum.filter(reports, &(&1.role == role))
        calls = Enum.sum(Enum.map(rs, & &1.calls))
        bad = Enum.sum(Enum.map(rs, & &1.bad))
        samples = rs |> Enum.flat_map(& &1.samples) |> Enum.take(5)
        {role, calls, bad, samples}
      end

    for {role, calls, bad, samples} <- summary do
      IO.puts("  #{role}: calls=#{calls} ok=#{calls - bad} bad=#{bad}")
      Enum.each(samples, &IO.puts("    sample: #{inspect(&1)}"))
    end

    if crashed != [], do: IO.puts("  caller crashes/timeouts: #{inspect(crashed, limit: 5)}")

    killers_ok? = Enum.all?(summary, fn {role, calls, bad, _} -> role != :killer or (calls > 0 and bad == 0) end)
    healthy_ok? = Enum.all?(summary, fn {role, calls, bad, _} -> role != :healthy or (calls > 0 and bad == 0) end)

    killers_ok? and healthy_ok? and crashed == []
  end

  defp caller(n, deadline) do
    role = if n < @killers, do: :killer, else: :healthy
    op = if role == :killer, do: &killer_op/1, else: &healthy_op/1
    loop(role, op, n, deadline, %{role: role, calls: 0, bad: 0, samples: []})
  end

  defp loop(role, op, i, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      acc =
        case safe(op, i) do
          :ok -> %{acc | calls: acc.calls + 1}
          {:bad, reason} -> %{acc | calls: acc.calls + 1, bad: acc.bad + 1, samples: Enum.take([reason | acc.samples], 3)}
        end

      loop(role, op, i + 1, deadline, acc)
    end
  end

  defp safe(op, i) do
    op.(i)
  catch
    kind, reason -> {:bad, {:raised, kind, inspect(reason)}}
  end

  # ---- sweep ----

  defp sweep(sup, seconds) do
    IO.puts("\nS5 concurrency sweep (healthy point lookup + join, #{seconds}s per level)")
    IO.puts("  C    calls   bad  mean_latency_us")

    prev =
      Enum.reduce([1, 4, 16, 64, 256], nil, fn c, prev ->
        deadline = System.monotonic_time(:millisecond) + seconds * 1000

        stats =
          sup
          |> Task.Supervisor.async_stream_nolink(1..c, fn n -> timed_loop(n, deadline, {0, 0, 0}) end,
            max_concurrency: c,
            timeout: seconds * 1000 + 120_000,
            on_timeout: :kill_task,
            ordered: false
          )
          |> Enum.reduce({0, 0, 0}, fn
            {:ok, {calls, bad, us}}, {c0, b0, u0} -> {c0 + calls, b0 + bad, u0 + us}
            _crashed, {c0, b0, u0} -> {c0, b0 + 1, u0}
          end)

        {calls, bad, us} = stats
        mean = if calls > 0, do: us / calls, else: 0.0
        knee = if prev != nil and prev > 0 and mean > 2 * prev, do: "  <-- knee (>2x previous level)", else: ""
        IO.puts("  #{String.pad_trailing(Integer.to_string(c), 4)} #{String.pad_trailing(Integer.to_string(calls), 8)}#{String.pad_trailing(Integer.to_string(bad), 6)}#{Float.round(mean * 1.0, 1)}#{knee}")
        mean
      end)

    prev
  end

  defp timed_loop(i, deadline, {calls, bad, us} = acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      t0 = System.monotonic_time(:microsecond)
      outcome = safe(&healthy_op/1, i)
      dt = System.monotonic_time(:microsecond) - t0
      bad = if outcome == :ok, do: bad, else: bad + 1
      timed_loop(i + 1, deadline, {calls + 1, bad, us + dt})
    end
  end
end

S5.Storm.main(System.argv())
