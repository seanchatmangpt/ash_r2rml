# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAInMemoryJoinsEncodingTest do
  @moduledoc """
  Exact-state tests for `AshR2RML.OBDA.InMemory`: cross-resource joins through
  `ReferenceObjectMap`, composite (multi-column) join conditions, percent-encoding of
  template-substituted values, nil handling and empty datasets.

  Real `Ash.DataLayer.Ets` rows (private tables), real `Ash.create!/read!`, real
  `RDF.Graph`, real SPARQL engine. Mappings are hand-built IR (same pattern as
  `Warehouse` in `test/support/grand_example/resources.ex`) because the composite
  natural-key templates deliberately omit the physical `{id}` placeholder.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA.InMemory

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAInMemoryJoinsEncodingTest.Org
      resource AshR2RML.OBDAInMemoryJoinsEncodingTest.Person
      resource AshR2RML.OBDAInMemoryJoinsEncodingTest.Warehouse
      resource AshR2RML.OBDAInMemoryJoinsEncodingTest.Shipment
      resource AshR2RML.OBDAInMemoryJoinsEncodingTest.Item
    end
  end

  defmodule Org do
    use Ash.Resource, domain: AshR2RML.OBDAInMemoryJoinsEncodingTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:code, :name]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :code, :string, public?: true
      attribute :name, :string, public?: true
    end
  end

  defmodule Person do
    use Ash.Resource, domain: AshR2RML.OBDAInMemoryJoinsEncodingTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:pid, :name, :org_code]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :pid, :string, public?: true
      attribute :name, :string, public?: true
      attribute :org_code, :string, public?: true
    end
  end

  defmodule Warehouse do
    use Ash.Resource, domain: AshR2RML.OBDAInMemoryJoinsEncodingTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:region, :code]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :region, :string, public?: true
      attribute :code, :string, public?: true
    end
  end

  defmodule Shipment do
    use Ash.Resource, domain: AshR2RML.OBDAInMemoryJoinsEncodingTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:sid, :region, :warehouse_code]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :sid, :string, public?: true
      attribute :region, :string, public?: true
      attribute :warehouse_code, :string, public?: true
    end
  end

  defmodule Item do
    use Ash.Resource, domain: AshR2RML.OBDAInMemoryJoinsEncodingTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:slug, :name]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :slug, :string, public?: true
      attribute :name, :string, public?: true
    end
  end

  @ex "https://ex.org/"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @name "https://schema.org/name"
  @member_of "https://schema.org/memberOf"
  @ships_from "https://ex.org/shipsFrom"

  # -- builders ---------------------------------------------------------------

  defp pom(attribute, predicate) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: predicate,
      object_map: %ObjectMap{strategy: :column, value: Atom.to_string(attribute)}
    }
  end

  defp mapping(resource, template, class, poms, refs \\ []) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: :template, value: template},
      class_iris: [class],
      predicate_object_maps: poms,
      reference_object_maps: refs
    }
  end

  defp org_mapping, do: mapping(Org, @ex <> "org/{code}", @ex <> "Org", [pom(:name, @name)])

  defp person_mapping do
    ref = %ReferenceObjectMap{
      relationship: :org,
      predicate_iri: @member_of,
      parent_resource: Org,
      joins: [%JoinCondition{child: "org_code", parent: "code"}]
    }

    mapping(Person, @ex <> "person/{pid}", @ex <> "Person", [pom(:name, @name)], [ref])
  end

  defp warehouse_mapping, do: mapping(Warehouse, @ex <> "wh/{region}/{code}", @ex <> "Warehouse", [])

  defp shipment_mapping do
    ref = %ReferenceObjectMap{
      relationship: :warehouse,
      predicate_iri: @ships_from,
      parent_resource: Warehouse,
      joins: [
        %JoinCondition{child: "region", parent: "region"},
        %JoinCondition{child: "warehouse_code", parent: "code"}
      ]
    }

    mapping(Shipment, @ex <> "shipment/{sid}", @ex <> "Shipment", [], [ref])
  end

  defp item_mapping(template \\ @ex <> "item/{slug}"),
    do: mapping(Item, template, @ex <> "Item", [pom(:name, @name)])

  defp create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, domain: Dom)
    |> Ash.create!(domain: Dom)
  end

  defp triples({:ok, %RDF.Graph{} = graph}), do: graph |> RDF.Graph.triples() |> MapSet.new()

  defp t(s, p, o) when is_binary(o) and binary_part(o, 0, 4) == "http",
    do: {RDF.iri(s), RDF.iri(p), RDF.iri(o)}

  defp t(s, p, o), do: {RDF.iri(s), RDF.iri(p), RDF.literal(o)}

  defp ty(s, class), do: {RDF.iri(s), RDF.iri(@rdf_type), RDF.iri(class)}
  defp lit(s, p, o), do: {RDF.iri(s), RDF.iri(p), RDF.literal(o)}

  # -- joins ------------------------------------------------------------------

  test "query_many joins Person to Org through a ReferenceObjectMap with exact rows" do
    create!(Org, %{code: "acme", name: "Acme"})
    create!(Org, %{code: "globex", name: "Globex"})
    create!(Person, %{pid: "p1", name: "Ann", org_code: "acme"})
    create!(Person, %{pid: "p2", name: "Bob", org_code: "globex"})
    create!(Person, %{pid: "p3", name: "Cy", org_code: nil})

    sparql = """
    SELECT ?person ?org ?orgname WHERE {
      ?person <#{@member_of}> ?org .
      ?org <#{@name}> ?orgname .
    }
    """

    assert {:ok, obs} =
             InMemory.query_many([{Person, person_mapping()}, {Org, org_mapping()}], sparql, domain: Dom)

    assert Enum.sort_by(obs.rows, & &1["person"]) == [
             %{"person" => @ex <> "person/p1", "org" => @ex <> "org/acme", "orgname" => "Acme"},
             %{"person" => @ex <> "person/p2", "org" => @ex <> "org/globex", "orgname" => "Globex"}
           ]
  end

  test "reference to a parent resource absent from the call yields no relationship triple" do
    create!(Person, %{pid: "p1", name: "Ann", org_code: "acme"})

    assert triples(InMemory.materialize(Person, person_mapping(), domain: Dom)) ==
             MapSet.new([ty(@ex <> "person/p1", @ex <> "Person"), lit(@ex <> "person/p1", @name, "Ann")])
  end

  # -- materialize_many -------------------------------------------------------

  test "materialize_many for two specs yields exactly the union of triples" do
    create!(Org, %{code: "acme", name: "Acme"})
    create!(Person, %{pid: "p1", name: "Ann", org_code: "acme"})

    assert triples(InMemory.materialize_many([{Org, org_mapping()}, {Person, person_mapping()}], domain: Dom)) ==
             MapSet.new([
               ty(@ex <> "org/acme", @ex <> "Org"),
               lit(@ex <> "org/acme", @name, "Acme"),
               ty(@ex <> "person/p1", @ex <> "Person"),
               lit(@ex <> "person/p1", @name, "Ann"),
               t(@ex <> "person/p1", @member_of, @ex <> "org/acme")
             ])
  end

  # -- composite joins --------------------------------------------------------

  test "composite two-column JoinCondition resolves the parent natural-key IRI" do
    create!(Warehouse, %{region: "emea", code: "w1"})
    create!(Warehouse, %{region: "apac", code: "w1"})
    create!(Shipment, %{sid: "s1", region: "emea", warehouse_code: "w1"})
    create!(Shipment, %{sid: "s2", region: "apac", warehouse_code: "w1"})
    create!(Shipment, %{sid: "s3", region: "emea", warehouse_code: nil})

    specs = [{Shipment, shipment_mapping()}, {Warehouse, warehouse_mapping()}]

    sparql = "SELECT ?s ?w WHERE { ?s <#{@ships_from}> ?w }"
    assert {:ok, obs} = InMemory.query_many(specs, sparql, domain: Dom)

    assert Enum.sort_by(obs.rows, & &1["s"]) == [
             %{"s" => @ex <> "shipment/s1", "w" => @ex <> "wh/emea/w1"},
             %{"s" => @ex <> "shipment/s2", "w" => @ex <> "wh/apac/w1"}
           ]
  end

  # -- percent-encoding -------------------------------------------------------

  test "template-substituted special characters are percent-encoded in subject IRIs" do
    create!(Item, %{slug: "a b", name: "space"})
    create!(Item, %{slug: "a/b", name: "slash"})
    create!(Item, %{slug: "a#b", name: "hash"})
    create!(Item, %{slug: "café", name: "unicode"})

    base = @ex <> "item/"

    assert triples(InMemory.materialize(Item, item_mapping(), domain: Dom)) ==
             MapSet.new(
               for {iri, name} <- [
                     {base <> "a%20b", "space"},
                     {base <> "a%2Fb", "slash"},
                     {base <> "a%23b", "hash"},
                     {base <> "caf%C3%A9", "unicode"}
                   ],
                   triple <- [ty(iri, @ex <> "Item"), lit(iri, @name, name)],
                   do: triple
             )
  end

  test "static template text is not encoded, only the substituted value" do
    create!(Item, %{slug: "x y", name: "n"})

    mapping = item_mapping(@ex <> "static/path#frag-{slug}")

    assert triples(InMemory.materialize(Item, mapping, domain: Dom)) ==
             MapSet.new([
               ty(@ex <> "static/path#frag-x%20y", @ex <> "Item"),
               lit(@ex <> "static/path#frag-x%20y", @name, "n")
             ])
  end

  test "composite join object IRI percent-encodes substituted child values" do
    create!(Warehouse, %{region: "eu west", code: "w/1"})
    create!(Shipment, %{sid: "s1", region: "eu west", warehouse_code: "w/1"})

    graph =
      triples(
        InMemory.materialize_many([{Shipment, shipment_mapping()}, {Warehouse, warehouse_mapping()}], domain: Dom)
      )

    assert t(@ex <> "shipment/s1", @ships_from, @ex <> "wh/eu%20west/w%2F1") in graph
    assert ty(@ex <> "wh/eu%20west/w%2F1", @ex <> "Warehouse") in graph
  end

  # -- nil handling -----------------------------------------------------------

  test "nil attribute value omits only that triple, no crash" do
    create!(Item, %{slug: "k", name: nil})

    assert triples(InMemory.materialize(Item, item_mapping(), domain: Dom)) ==
             MapSet.new([ty(@ex <> "item/k", @ex <> "Item")])
  end

  test "subject template with nil field omits the whole row, other rows survive" do
    create!(Item, %{slug: nil, name: "ghost"})
    create!(Item, %{slug: "ok", name: "real"})

    assert triples(InMemory.materialize(Item, item_mapping(), domain: Dom)) ==
             MapSet.new([ty(@ex <> "item/ok", @ex <> "Item"), lit(@ex <> "item/ok", @name, "real")])
  end

  # -- empty dataset ----------------------------------------------------------

  test "empty dataset: materialize returns an empty graph and query returns zero rows" do
    assert {:ok, %RDF.Graph{} = graph} = InMemory.materialize(Item, item_mapping(), domain: Dom)
    assert RDF.Graph.triples(graph) == []

    assert {:ok, obs} = InMemory.query(Item, item_mapping(), "SELECT ?s ?n WHERE { ?s <#{@name}> ?n }", domain: Dom)
    assert obs.rows == []

    assert {:ok, many} =
             InMemory.query_many(
               [{Person, person_mapping()}, {Org, org_mapping()}],
               "SELECT ?p ?o WHERE { ?p <#{@member_of}> ?o }",
               domain: Dom
             )

    assert many.rows == []
  end
end
