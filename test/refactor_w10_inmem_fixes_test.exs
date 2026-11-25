# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW10InmemFixesTest do
  @moduledoc """
  (1) Subject templates, graph templates and join keys name storage COLUMNS; an attribute with a
  `source:` rename must resolve through the resource attributes, so the reference triple is
  emitted. (2) `GRAPH ?g` stops accumulating per-graph rows once the running merged count
  exceeds `max_rows` and returns `REFUSED_RESULT_LIMIT_EXCEEDED`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    GraphMap,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW10InmemFixesTest.Org
      resource AshR2RML.RefactorW10InmemFixesTest.Person
      resource AshR2RML.RefactorW10InmemFixesTest.Doc
    end
  end

  defmodule Org do
    use Ash.Resource, domain: AshR2RML.RefactorW10InmemFixesTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:code]])
    end

    identities do
      identity(:by_code, [:code], pre_check_with: AshR2RML.RefactorW10InmemFixesTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:code, :string, allow_nil?: false, public?: true, source: :org_col)
    end
  end

  defmodule Person do
    use Ash.Resource, domain: AshR2RML.RefactorW10InmemFixesTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:name, :org_code]])
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.RefactorW10InmemFixesTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:org_code, :string, public?: true, source: :org_ref_col)
    end
  end

  defmodule Doc do
    use Ash.Resource, domain: AshR2RML.RefactorW10InmemFixesTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :graph]])
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.RefactorW10InmemFixesTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:graph, :string, public?: true)
    end
  end

  @member_of "http://schema.org/memberOf"
  @name_pred "http://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp specs do
    org = %Resource{
      ash_resource: Org,
      class_iris: ["http://schema.org/Thing"],
      logical_table: %LogicalTable{table_name: "orgs"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/org-{org_col}", term_type: :iri},
      metadata: %{attribute_columns: %{id: "id", code: "org_col"}},
      identities: [[:code]]
    }

    person = %Resource{
      ash_resource: Person,
      class_iris: ["http://schema.org/Thing"],
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/person-{name}", term_type: :iri},
      metadata: %{attribute_columns: %{id: "id", name: "name", org_code: "org_ref_col"}},
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :org,
          predicate_iri: @member_of,
          parent_resource: Org,
          joins: [%JoinCondition{child: "org_ref_col", parent: "org_col"}]
        }
      ],
      identities: [[:name]]
    }

    [{Org, org}, {Person, person}]
  end

  defp doc_mapping do
    %Resource{
      ash_resource: Doc,
      logical_table: %LogicalTable{table_name: "docs"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/doc-{title}", term_type: :iri},
      graph_maps: [%GraphMap{strategy: :column, value: "graph"}],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @name_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "title",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:title]]
    }
  end

  setup do
    for resource <- [Person, Org, Doc] do
      resource
      |> Ash.read!(domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, domain: Domain))
    end

    :ok
  end

  defp create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, domain: Domain)
    |> Ash.create!(domain: Domain)
  end

  test "join key and subject template over `source`-renamed attributes emit the reference triple" do
    create!(Org, %{code: "a"})
    create!(Person, %{name: "p1", org_code: "a"})

    select = "SELECT ?p ?o WHERE { ?p <#{@member_of}> ?o }"
    assert {:ok, result} = OBDA.query(specs(), select, domain: Domain)

    assert Enum.map(result.bindings, &{to_string(&1["p"]), to_string(&1["o"])}) ==
             [{"http://schema.org/person-p1", "http://schema.org/org-a"}]
  end

  test "GRAPH ?g refuses once the running merged count exceeds max_rows" do
    for n <- 1..4, do: create!(Doc, %{title: "t#{n}", graph: "http://schema.org/graph-#{n}"})

    select = "SELECT ?g ?s ?o WHERE { GRAPH ?g { ?s <#{@name_pred}> ?o } }"

    assert {:error, %{code: :REFUSED_RESULT_LIMIT_EXCEEDED}} =
             InMemory.query(Doc, doc_mapping(), select, domain: Domain, max_rows: 2)

    assert {:ok, observation} = InMemory.query(Doc, doc_mapping(), select, domain: Domain, max_rows: 4)
    assert length(observation.rows) == 4
  end
end
