# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2InmemoryPerfTest do
  @moduledoc """
  Bounded-work laws for the in-memory OBDA backend: reference joins and paginated
  reads must scale to thousands of rows, and a query refused by `GraphQuery.plan/1`
  must refuse before any Ash read happens.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    JoinCondition,
    LogicalTable,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA.InMemory

  @counter :red2_inmemory_perf_reads
  @deadline_ms 20_000

  defmodule CountReads do
    @moduledoc false
    use Ash.Resource.Preparation

    @impl true
    def prepare(query, _opts, _context) do
      :ets.update_counter(:red2_inmemory_perf_reads, :reads, 1, {:reads, 0})
      query
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Red2InmemoryPerfTest.Parent
      resource AshR2RML.Red2InmemoryPerfTest.Child
      resource AshR2RML.Red2InmemoryPerfTest.Paged
      resource AshR2RML.Red2InmemoryPerfTest.Counted
    end
  end

  defmodule Parent do
    use Ash.Resource,
      domain: AshR2RML.Red2InmemoryPerfTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:key])
      read :read, primary?: true
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:key, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Child do
    use Ash.Resource,
      domain: AshR2RML.Red2InmemoryPerfTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:key, :fk])
      read :read, primary?: true
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:key, :string, allow_nil?: false, public?: true)
      attribute(:fk, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Paged do
    use Ash.Resource,
      primary_read_warning?: false,
      domain: AshR2RML.Red2InmemoryPerfTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:key])

      read :read do
        primary?(true)
        pagination(offset?: true, required?: true, default_limit: 500, max_page_size: 500)
        prepare(build(sort: [key: :asc]))
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:key, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Counted do
    use Ash.Resource,
      primary_read_warning?: false,
      domain: AshR2RML.Red2InmemoryPerfTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults(create: [:key])

      read :read do
        primary?(true)
        prepare(AshR2RML.Red2InmemoryPerfTest.CountReads)
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:key, :string, allow_nil?: false, public?: true)
    end
  end

  setup do
    :ets.new(@counter, [:public, :named_table])
    :ok
  end

  defp reads, do: :ets.lookup(@counter, :reads) |> Enum.map(&elem(&1, 1)) |> Enum.sum()

  defp mapping(resource, prefix, refs \\ []) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: prefix},
      subject_map: %SubjectMap{
        strategy: :template,
        value: "urn:uuid:#{prefix}-{key}",
        term_type: :iri
      },
      class_iris: ["http://schema.org/Thing"],
      reference_object_maps: refs,
      identities: [],
      metadata: %{source: :red2_inmemory_perf_test}
    }
  end

  defp seed(resource, inputs) do
    Ash.bulk_create!(inputs, resource, :create,
      domain: Domain,
      authorize?: false,
      return_errors?: true
    )

    :ok
  end

  defp timed(fun) do
    {micros, result} = :timer.tc(fun)
    {div(micros, 1000), result}
  end

  test "3000 x 3000 reference join resolves every row within the deadline" do
    n = 3000
    keys = for i <- 1..n, do: "k#{i}"

    seed(Parent, Enum.map(keys, &%{key: &1}))
    seed(Child, Enum.map(keys, &%{key: &1, fk: &1}))

    ref = %ReferenceObjectMap{
      relationship: :parent,
      predicate_iri: "http://schema.org/isPartOf",
      parent_resource: Parent,
      joins: [%JoinCondition{child: "fk", parent: "key"}]
    }

    specs = [
      {Parent, mapping(Parent, "p")},
      {Child, mapping(Child, "c", [ref])}
    ]

    sparql = "SELECT ?c ?p WHERE { ?c <http://schema.org/isPartOf> ?p }"

    {ms, {result, stats}} =
      timed(fn ->
        InMemory.query_with_stats(specs, sparql,
          domain: Domain,
          max_rows: 20_000,
          max_triples: 200_000
        )
      end)

    assert {:ok, observation} = result
    assert stats.rows_read == 2 * n
    assert length(observation.rows) == n

    assert Enum.all?(observation.rows, fn b ->
             "urn:uuid:p-" <> k = to_string(b["p"])
             to_string(b["c"]) == "urn:uuid:c-" <> k
           end)

    assert ms < @deadline_ms, "reference join took #{ms}ms (deadline #{@deadline_ms}ms)"
  end

  test "5000-row required-pagination read returns every row within the deadline" do
    n = 5000
    seed(Paged, for(i <- 1..n, do: %{key: "k#{i}"}))

    specs = [{Paged, mapping(Paged, "pg")}]
    sparql = "SELECT ?s WHERE { ?s a <http://schema.org/Thing> }"

    {ms, {result, stats}} =
      timed(fn ->
        InMemory.query_with_stats(specs, sparql,
          domain: Domain,
          max_rows: 20_000,
          max_triples: 200_000
        )
      end)

    assert {:ok, observation} = result
    assert stats.rows_read == n
    assert length(observation.rows) == n
    assert ms < @deadline_ms, "paginated read took #{ms}ms (deadline #{@deadline_ms}ms)"
  end

  test "an invalid GRAPH query is refused before any Ash read" do
    seed(Counted, [%{key: "a"}, %{key: "b"}])
    specs = [{Counted, mapping(Counted, "ct")}]

    invalid = "SELECT ?s WHERE { GRAPH ?g { ?s a <http://schema.org/Thing> } } LIMIT 1"

    assert {{:error, refusal}, stats} =
             InMemory.query_with_stats(specs, invalid, domain: Domain)

    assert refusal.code == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
    assert reads() == 0, "refused query still performed #{reads()} Ash read(s)"
    assert stats.rows_read == 0

    # Control: a valid query on the same resource does read through the counted action.
    valid = "SELECT ?s WHERE { ?s a <http://schema.org/Thing> }"
    assert {{:ok, observation}, _} = InMemory.query_with_stats(specs, valid, domain: Domain)
    assert length(observation.rows) == 2
    assert reads() > 0
  end
end
