# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupCompositeValueTest do
  @moduledoc """
  A join child column holding a value with no `String.Chars` (a plain `:map` attribute) must
  drop only that reference triple; it never raises out of `AshR2RML.OBDA.InMemory`.

  Real `Ash.DataLayer.Ets` rows, real `Ash.create!/2`, hand-built mapping IR.
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
      resource AshR2RML.FollowupCompositeValueTest.Parent
      resource AshR2RML.FollowupCompositeValueTest.Child
    end
  end

  defmodule Parent do
    use Ash.Resource, domain: AshR2RML.FollowupCompositeValueTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
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

  defmodule Child do
    use Ash.Resource, domain: AshR2RML.FollowupCompositeValueTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:sid, :ref]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :sid, :string, public?: true
      attribute :ref, :map, public?: true
    end
  end

  @base "http://schema.org/"
  @member_of "http://schema.org/memberOf"
  @name "http://schema.org/name"

  defp mapping(resource, template, class, poms, refs) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: :template, value: template},
      class_iris: [class],
      predicate_object_maps: poms,
      reference_object_maps: refs
    }
  end

  defp parent_mapping(subject_map \\ nil) do
    name_pom = %PredicateObjectMap{
      attribute: :name,
      predicate_iri: @name,
      object_map: %ObjectMap{strategy: :column, value: "name"}
    }

    base = mapping(Parent, @base <> "parent-{code}", @base <> "Organization", [name_pom], [])
    if subject_map, do: %{base | subject_map: subject_map}, else: base
  end

  defp child_mapping do
    ref = %ReferenceObjectMap{
      relationship: :parent,
      predicate_iri: @member_of,
      parent_resource: Parent,
      joins: [%JoinCondition{child: "ref", parent: "code"}]
    }

    mapping(Child, @base <> "child-{sid}", @base <> "Person", [], [ref])
  end

  defp create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, domain: Dom)
    |> Ash.create!(domain: Dom)
  end

  defp member_of_triples(graph) do
    graph |> RDF.Graph.triples() |> Enum.filter(fn {_s, p, _o} -> p == RDF.iri(@member_of) end)
  end

  test "map-valued join child under a template parent drops the reference, no raise" do
    create!(Parent, %{code: "a", name: "A"})
    create!(Child, %{sid: "c1", ref: %{"k" => "v"}})
    create!(Child, %{sid: "c2", ref: nil})

    specs = [{Child, child_mapping()}, {Parent, parent_mapping()}]

    assert {:ok, %RDF.Graph{} = graph} = InMemory.materialize_many(specs, domain: Dom)
    assert member_of_triples(graph) == []

    subjects = graph |> RDF.Graph.subjects() |> MapSet.new(&to_string/1)
    assert MapSet.member?(subjects, @base <> "child-c1")
    assert MapSet.member?(subjects, @base <> "parent-a")
  end

  test "map-valued join child under a column parent drops the reference, no raise" do
    create!(Parent, %{code: "http://schema.org/parent-a", name: "A"})
    create!(Child, %{sid: "c1", ref: %{"k" => "v"}})

    column = %SubjectMap{strategy: :column, value: "code"}
    specs = [{Child, child_mapping()}, {Parent, parent_mapping(column)}]

    assert {:ok, %RDF.Graph{} = graph} = InMemory.materialize_many(specs, domain: Dom)
    assert member_of_triples(graph) == []
  end
end
