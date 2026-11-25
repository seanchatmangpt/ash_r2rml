# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ObdaObjectMapsAndTripleClampTest do
  @moduledoc """
  Template/constant object maps are IRIs or typed refusals (never silent literals), and the
  `max_triples` bound trips from a single clamped read.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ObdaObjectMapsAndTripleClampTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource, domain: AshR2RML.ObdaObjectMapsAndTripleClampTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:key, :name, :oid, :age]
      end
    end

    attributes do
      attribute :key, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, allow_nil?: false, public?: true
      attribute :oid, :string, public?: true
      attribute :age, :integer, public?: true
    end
  end

  @ex "urn:uuid:"
  @name "https://schema.org/name"
  @member "https://schema.org/memberOf"

  defp mapping(extra_poms) do
    %Resource{
      ash_resource: Item,
      logical_table: %LogicalTable{table_name: "items"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "item-{key}"},
      class_iris: ["https://schema.org/Thing"],
      identities: [[:key]],
      predicate_object_maps:
        [
          %PredicateObjectMap{
            attribute: :name,
            predicate_iri: @name,
            object_map: %ObjectMap{strategy: :column, value: "name"}
          }
        ] ++ extra_poms
    }
  end

  # Read-only suite: seed once from setup_all so its long-lived process owns the table.
  # No test mutates rows, so no per-test cleanup is needed.
  setup_all do
    Ash.DataLayer.Ets.stop(Item)

    for i <- 1..50 do
      Item
      |> Ash.Changeset.for_create(:create, %{key: "k#{i}", name: "n#{i}", oid: "o#{i}", age: i}, domain: Dom)
      |> Ash.create!(domain: Dom)
    end

    :ok
  end

  test "an :iri template object map emits a real IRI, never a literal" do
    pom = %PredicateObjectMap{
      attribute: :oid,
      predicate_iri: @member,
      object_map: %ObjectMap{strategy: :template, value: @ex <> "org-{oid}", term_type: :iri}
    }

    assert {:ok, graph} = InMemory.materialize(Item, mapping([pom]), domain: Dom)

    objects =
      graph
      |> RDF.Graph.triples()
      |> Enum.filter(fn {_s, p, _o} -> to_string(p) == @member end)
      |> Enum.map(fn {_s, _p, o} -> o end)

    assert length(objects) == 50
    assert Enum.all?(objects, &match?(%RDF.IRI{}, &1))
    assert RDF.iri(@ex <> "org-o7") in objects
  end

  test "a literal-typed template object map is a typed refusal, not a silent literal" do
    pom = %PredicateObjectMap{
      attribute: :oid,
      predicate_iri: @member,
      object_map: %ObjectMap{strategy: :template, value: @ex <> "org-{oid}", term_type: :literal}
    }

    assert {:error, %Refusal{code: :UNSUPPORTED_TERM_TYPE}} = InMemory.materialize(Item, mapping([pom]), domain: Dom)
  end

  test "max_triples trips from the clamped read: rows beyond the budget are never materialized" do
    # 2 guaranteed triples per row (class + name) -> budget 10 allows 5 rows; 50 rows exist.
    assert {:error, %Refusal{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}} =
             InMemory.materialize(Item, mapping([]), domain: Dom, max_triples: 10)

    {{:error, %Refusal{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}}, stats} =
      InMemory.query_with_stats([{Item, mapping([])}], "SELECT ?n WHERE { ?s <#{@name}> ?n }",
        domain: Dom,
        max_triples: 10
      )

    assert stats.rows_read == 0
  end

  test "declared datatypes materialize typed literals so numeric FILTER and ORDER BY are correct" do
    age = %PredicateObjectMap{
      attribute: :age,
      predicate_iri: "https://schema.org/age",
      object_map: %ObjectMap{
        strategy: :column,
        value: "age",
        datatype: %AshR2RML.Mapping.Datatype{
          ash_type: Ash.Type.Integer,
          rdf_datatype: "http://www.w3.org/2001/XMLSchema#integer"
        }
      }
    }

    sparql = "SELECT ?s ?a WHERE { ?s <https://schema.org/age> ?a . FILTER(?a >= 40) }"

    assert {{:ok, observation}, _stats} =
             InMemory.query_with_stats([{Item, mapping([age])}], sparql, domain: Dom)

    # numeric comparison over xsd:integer (a plain-string literal would yield 0 rows)
    assert length(observation.rows) == 11
  end

  test "an :iri object template over a non-attribute field is refused, never rendered into an IRI" do
    pom = %PredicateObjectMap{
      attribute: :oid,
      predicate_iri: @member,
      object_map: %ObjectMap{strategy: :template, value: @ex <> "org-{not_an_attribute}", term_type: :iri}
    }

    assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} =
             InMemory.materialize(Item, mapping([pom]), domain: Dom)
  end

  test "a budget that fits never drops valid rows" do
    assert {:ok, graph} = InMemory.materialize(Item, mapping([]), domain: Dom, max_triples: 100)
    assert RDF.Graph.triple_count(graph) == 100
  end
end
