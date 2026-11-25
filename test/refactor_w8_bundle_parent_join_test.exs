# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW8BundleParentJoinTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{JoinCondition, LogicalTable, ReferenceObjectMap, Resource, SubjectMap}
  alias AshR2RML.Mapping.Validate.BundleRules
  alias AshR2RML.Refusal

  defp parent do
    %Resource{
      ash_resource: ParentW8,
      logical_table: %LogicalTable{table_name: "orgs"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/org/{id}"},
      class_iris: ["http://schema.org/Organization"],
      identities: [[:id]],
      metadata: %{attribute_columns: %{id: "id", code: "code"}}
    }
  end

  defp child(joins) do
    ref = %ReferenceObjectMap{
      relationship: :org,
      predicate_iri: "http://schema.org/memberOf",
      parent_resource: ParentW8,
      joins: joins
    }

    %Resource{
      ash_resource: ChildW8,
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/person/{id}"},
      class_iris: ["http://schema.org/Person"],
      identities: [[:id]],
      reference_object_maps: [ref]
    }
  end

  defp check(joins), do: BundleRules.reference_targets(child(joins), %{ParentW8 => parent()})

  test "join on the parent identity column is accepted" do
    assert [] = check([%JoinCondition{child: "org_id", parent: "id"}])
  end

  test "join on a parent column the parent mapping lacks is refused" do
    assert [%Refusal{code: :REFUSED_INVALID_JOIN_CONDITION}] =
             check([%JoinCondition{child: "org_id", parent: "ghost"}])
  end

  test "join on an existing non-identity parent column stays lawful (has_many-style)" do
    assert [] = check([%JoinCondition{child: "org_code", parent: "code"}])
  end
end
