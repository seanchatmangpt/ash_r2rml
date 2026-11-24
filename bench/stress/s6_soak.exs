# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# S6 soak: 10_000 OBDA queries with unique dynamic IRIs / filter strings over real
# Ash.DataLayer.Ets rows. Snapshots every 1_000 runs of memory, atom count, ETS table count
# and process count. Breach (exit 1) when, after warmup:
#   * atom delta > 5
#   * ETS table count or process count differs from the post-warmup baseline
#   * post-GC total memory drift > 5%
#
# Run: mix run bench/stress/s6_soak.exs

defmodule S6Soak.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource S6Soak.Person
  end
end

defmodule S6Soak.Person do
  use Ash.Resource, domain: S6Soak.Dom, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pid, :name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :pid, :string, public?: true
    attribute :name, :string, public?: true
  end
end

defmodule S6Soak do
  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @ex "https://ex.org/"
  @name "https://schema.org/name"
  @total 10_000
  @warmup 500
  @every 1_000
  @atom_budget 5
  @mem_drift 0.05
  @settle_ms 5_000

  def main do
    {:ok, _} = Application.ensure_all_started(:ash_r2rml)
    Ash.DataLayer.Ets.stop(S6Soak.Person)

    for i <- 1..20 do
      S6Soak.Person
      |> Ash.Changeset.for_create(:create, %{pid: "p#{i}", name: "name-#{i}"}, domain: S6Soak.Dom)
      |> Ash.create!(domain: S6Soak.Dom)
    end

    # Preflight: the query shape must be answerable, otherwise the soak measures refusals.
    {:ok, _} = run_one(0)

    Enum.each(1..@warmup, &run_one(-&1))
    settle_gc()
    base = snapshot(:baseline)
    IO.puts(format(base))

    snaps =
      Enum.reduce(1..@total, [base], fn n, acc ->
        {:ok, _} = run_one(n)

        if rem(n, @every) == 0 do
          snap = snapshot(n)
          IO.puts(format(snap))
          [snap | acc]
        else
          acc
        end
      end)

    settle_gc()
    final = snapshot(:final)
    IO.puts(format(final))
    _ = snaps

    breaches = breaches(base, final)

    if breaches == [] do
      IO.puts("S6 SOAK PASS: #{@total} queries")
      System.halt(0)
    else
      Enum.each(breaches, &IO.puts(:stderr, "S6 SOAK BREACH: #{&1}"))
      System.halt(1)
    end
  end

  # Unique subject IRI and unique filter string per run; all binaries.
  defp run_one(n) do
    k = "u#{n}-#{System.unique_integer([:positive])}"

    sparql = """
    SELECT ?name WHERE {
      <#{@ex}person/#{k}> <#{@name}> ?name .
      FILTER(?name = "#{k}")
    }
    """

    case AshR2RML.OBDA.query([{S6Soak.Person, mapping()}], sparql, domain: S6Soak.Dom) do
      {:ok, _} = ok ->
        ok

      other ->
        IO.puts(:stderr, "S6 SOAK BREACH: query #{n} did not return {:ok, _}: #{inspect(other)}")
        System.halt(1)
    end
  end

  defp mapping do
    %Resource{
      ash_resource: S6Soak.Person,
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
      ]
    }
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

  defp format(s),
    do: "snapshot #{s.label}: memory=#{s.memory} atoms=#{s.atoms} ets=#{s.ets} procs=#{s.procs}"

  # Full GC, then bounded poll (deadline) until the process count stops moving.
  defp settle_gc do
    deadline = System.monotonic_time(:millisecond) + @settle_ms
    settle(deadline, -1)
  end

  defp settle(deadline, last) do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    now = :erlang.system_info(:process_count)

    cond do
      now == last ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :ok

      true ->
        # SLEEP-CLASS: POLL-STEP (bounded by deadline; yields to let exiting processes finish)
        receive do
        after
          25 -> :ok
        end

        settle(deadline, now)
    end
  end

  defp breaches(base, final) do
    drift = abs(final.memory - base.memory) / base.memory

    []
    |> add(final.atoms - base.atoms > @atom_budget, "atom delta #{final.atoms - base.atoms} > #{@atom_budget}")
    |> add(final.ets != base.ets, "ETS tables #{base.ets} -> #{final.ets}")
    |> add(final.procs != base.procs, "processes #{base.procs} -> #{final.procs}")
    |> add(drift > @mem_drift, "post-GC memory drift #{Float.round(drift * 100, 2)}% > #{@mem_drift * 100}%")
    |> Enum.reverse()
  end

  defp add(acc, true, msg), do: [msg | acc]
  defp add(acc, false, _msg), do: acc
end

S6Soak.main()
