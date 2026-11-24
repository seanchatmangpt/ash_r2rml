# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryCanonicalOrderTest do
  @moduledoc """
  PR-06: `AshR2RML.OBDA.InMemory` returns SELECT rows in canonical order when the SPARQL has
  no ORDER BY (independent of insertion order), and preserves engine order under ORDER BY.
  Real ETS resource, no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.SPARQL.Result

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryCanonicalOrderTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryCanonicalOrderTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:name]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  @pred "https://example.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @names ["mango", "zebra", "apple", "kiwi", "banana"]

  defp mapping do
    %Resource{
      ash_resource: Item,
      logical_table: %LogicalTable{table_name: "items"},
      subject_map: %SubjectMap{strategy: :template, value: "https://example.org/i/{name}", term_type: :iri},
      class_iris: [],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:id]],
      metadata: %{source: :canonical_order_test}
    }
  end

  defp reset(names) do
    Item |> Ash.read!(domain: Domain) |> Enum.each(&Ash.destroy!(&1, domain: Domain))

    for name <- names do
      Item |> Ash.Changeset.for_create(:create, %{name: name}, domain: Domain) |> Ash.create!(domain: Domain)
    end
  end

  defp run(names, sparql) do
    reset(names)
    InMemory.query(Item, mapping(), sparql, domain: Domain)
  end

  defp rows!(names, sparql) do
    assert {:ok, obs} = run(names, sparql)
    obs.rows
  end

  @select "SELECT ?s ?n WHERE { ?s <#{@pred}> ?n }"

  test "without ORDER BY, insertion order does not change row order" do
    forward = rows!(@names, @select)
    reversed = rows!(Enum.reverse(@names), @select)
    sorted_ins = rows!(Enum.sort(@names), @select)

    assert length(forward) == 5
    assert forward == reversed
    assert forward == sorted_ins
  end

  test "canonical order is ascending by binding terms" do
    rows = rows!(@names, @select)
    assert rows == Enum.sort_by(rows, fn row -> row |> Enum.to_list() |> Enum.sort() end)
  end

  test "hash_rows is equal across insertion orders" do
    a = @names |> rows!(@select) |> Result.hash_rows()
    b = @names |> Enum.reverse() |> rows!(@select) |> Result.hash_rows()
    assert a == b
  end

  test "ORDER BY DESC(?name) yields descending name order, not canonical" do
    sparql = "SELECT ?n WHERE { ?s <#{@pred}> ?n } ORDER BY DESC(?n)"

    for names <- [@names, Enum.reverse(@names)] do
      got = names |> rows!(sparql) |> Enum.map(&to_string(&1["n"]))
      assert got == Enum.sort(@names, :desc)
    end
  end

  test "ASK is unaffected by insertion order" do
    ask = "ASK { ?s <#{@pred}> \"kiwi\" }"
    assert {:ok, a} = run(@names, ask)
    assert {:ok, b} = run(Enum.reverse(@names), ask)
    assert a.result_kind != :bindings
    assert a == b
  end

  test "CONSTRUCT is unaffected by insertion order" do
    construct = "CONSTRUCT { ?s <#{@pred}> ?n } WHERE { ?s <#{@pred}> ?n }"
    a = run(@names, construct)
    b = run(Enum.reverse(@names), construct)

    case a do
      {:ok, obs} -> refute obs.result_kind == :bindings
      {:error, _} -> :ok
    end

    assert a == b
  end
end
