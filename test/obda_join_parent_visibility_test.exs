# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAJoinParentVisibilityTest do
  @moduledoc """
  Child->parent reference objects are built from the FK value alone; they must only be emitted
  for parent subjects actually materialized for the actor (parent row-filter policy), or the
  child's FK discloses keys of parent rows the actor cannot read.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDAJoinParentVisibilityTest.Org
      resource AshR2RML.OBDAJoinParentVisibilityTest.Person
    end
  end

  defmodule Org do
    use Ash.Resource,
      domain: AshR2RML.OBDAJoinParentVisibilityTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:code]])
    end

    policies do
      policy action_type(:read) do
        authorize_if(expr(code == ^actor(:org_code)))
      end
    end

    identities do
      identity(:by_code, [:code], pre_check_with: AshR2RML.OBDAJoinParentVisibilityTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:code, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.OBDAJoinParentVisibilityTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:name, :org_code]])
    end

    policies do
      policy always() do
        authorize_if(always())
      end
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.OBDAJoinParentVisibilityTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:org_code, :string, public?: true)
    end
  end

  @ex "https://example.org/"
  @member_of @ex <> "memberOf"
  @name_pred @ex <> "name"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp specs do
    org = %Resource{
      ash_resource: Org,
      logical_table: %LogicalTable{table_name: "orgs"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "orgs/{code}", term_type: :iri},
      class_iris: [@ex <> "Org"],
      identities: [[:code]],
      metadata: %{source: :obda_join_parent_visibility_test}
    }

    person = %Resource{
      ash_resource: Person,
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "people/{name}", term_type: :iri},
      class_iris: [@ex <> "Person"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :org,
          predicate_iri: @member_of,
          parent_resource: Org,
          joins: [%JoinCondition{child: "org_code", parent: "code"}]
        }
      ],
      identities: [[:name]],
      metadata: %{source: :obda_join_parent_visibility_test}
    }

    [{Org, org}, {Person, person}]
  end

  @select "SELECT ?p ?o WHERE { ?p <#{@member_of}> ?o }"

  setup do
    for resource <- [Person, Org] do
      resource
      |> Ash.read!(authorize?: false, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))
    end

    for code <- ["a", "b"] do
      Org
      |> Ash.Changeset.for_create(:create, %{code: code}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    for {name, org} <- [{"p1", "a"}, {"p2", "b"}] do
      Person
      |> Ash.Changeset.for_create(:create, %{name: name, org_code: org}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    :ok
  end

  defp pairs(%OBDA.Result{bindings: rows}),
    do: rows |> Enum.map(&{to_string(&1["p"]), to_string(&1["o"])}) |> Enum.sort()

  test "actor of org a: only the visible parent is referenced; the invisible one is not disclosed" do
    assert {:ok, result} = OBDA.query(specs(), @select, domain: Domain, actor: %{org_code: "a"})
    assert pairs(result) == [{@ex <> "people/p1", @ex <> "orgs/a"}]
    refute inspect(result) =~ "orgs/b"
  end

  test "actor of org b sees the mirror image" do
    assert {:ok, result} = OBDA.query(specs(), @select, domain: Domain, actor: %{org_code: "b"})
    assert pairs(result) == [{@ex <> "people/p2", @ex <> "orgs/b"}]
  end

  test "actor of an org with no people: no memberOf triple and no foreign key leaks" do
    Org
    |> Ash.Changeset.for_create(:create, %{code: "c"}, domain: Domain)
    |> Ash.create!(authorize?: false, domain: Domain)

    assert {:ok, result} = OBDA.query(specs(), @select, domain: Domain, actor: %{org_code: "c"})
    assert result.bindings == []
  end
end
