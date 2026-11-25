# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW16JoinParentTest do
  @moduledoc """
  A reference join resolves the parent row by the declared `JoinCondition.parent` column and
  uses that row's own subject IRI, even when the join column is not the subject key column.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{JoinCondition, LogicalTable, ReferenceObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW16JoinParentTest.Org
      resource AshR2RML.RefactorW16JoinParentTest.Person
    end
  end

  defmodule Org do
    use Ash.Resource, domain: AshR2RML.RefactorW16JoinParentTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:slug, :code]])
    end

    identities do
      identity(:by_slug, [:slug], pre_check_with: AshR2RML.RefactorW16JoinParentTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:slug, :string, allow_nil?: false, public?: true)
      attribute(:code, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Person do
    use Ash.Resource, domain: AshR2RML.RefactorW16JoinParentTest.Domain, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:name, :org_code]])
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.RefactorW16JoinParentTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:org_code, :string, public?: true)
    end
  end

  @member_of "http://schema.org/memberOf"

  defp specs do
    org = %Resource{
      ash_resource: Org,
      logical_table: %LogicalTable{table_name: "orgs"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:org-{slug}", term_type: :iri},
      class_iris: ["http://schema.org/Organization"],
      identities: [[:slug]],
      metadata: %{
        source: :refactor_w16_join_parent_test,
        attribute_columns: %{id: "id", slug: "slug", code: "code"}
      }
    }

    person = %Resource{
      ash_resource: Person,
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:person-{name}", term_type: :iri},
      class_iris: ["http://schema.org/Person"],
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :org,
          predicate_iri: @member_of,
          parent_resource: Org,
          joins: [%JoinCondition{child: "org_code", parent: "code"}]
        }
      ],
      identities: [[:name]],
      metadata: %{source: :refactor_w16_join_parent_test}
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

    for {slug, code} <- [{"alpha", "7"}, {"7", "9"}] do
      Org
      |> Ash.Changeset.for_create(:create, %{slug: slug, code: code}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    for {name, org_code} <- [{"p1", "7"}, {"p2", "1"}] do
      Person
      |> Ash.Changeset.for_create(:create, %{name: name, org_code: org_code}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    :ok
  end

  test "join column differs from subject key: child fk 7 resolves to the parent whose code is 7" do
    assert {:ok, result} = OBDA.query(specs(), @select, domain: Domain)

    pairs = result.bindings |> Enum.map(&{to_string(&1["p"]), to_string(&1["o"])}) |> Enum.sort()

    # Org slug "7" (code 9) must NOT be matched; org slug "alpha" has code 7. p2 (fk 1) matches none.
    assert pairs == [{"urn:uuid:person-p1", "urn:uuid:org-alpha"}]
  end
end
