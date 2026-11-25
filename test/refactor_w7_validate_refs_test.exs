# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7ValidateRefsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{JoinCondition, LogicalTable, ReferenceObjectMap, Resource, SubjectMap}

  defp resource(joins) do
    %Resource{
      ash_resource: :Order,
      logical_table: %LogicalTable{table_name: "orders"},
      class_iris: ["http://schema.org/Order"],
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
      identities: [[:id]],
      metadata: %{attribute_columns: %{id: "id", customer_id: "customer_id"}},
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :customer,
          predicate_iri: "http://schema.org/customer",
          parent_resource: :Customer,
          joins: joins
        }
      ]
    }
  end

  test "join on declared child column is accepted" do
    assert :ok = Mapping.validate(resource([%JoinCondition{child: "customer_id", parent: "id"}]))
  end

  test "join naming a column absent from the child mapping is refused" do
    assert {:error, refusals} =
             Mapping.validate(resource([%JoinCondition{child: "ghost_col", parent: "id"}]))

    assert [refusal] = Enum.filter(refusals, &(&1.code == :REFUSED_INVALID_JOIN_CONDITION))
    assert refusal.evidence.side == :child
    assert refusal.evidence.column == "ghost_col"
  end

  test "self-referential join naming a missing parent column is refused" do
    mapping = resource([%JoinCondition{child: "customer_id", parent: "ghost_parent"}])
    [reference] = mapping.reference_object_maps
    mapping = %{mapping | reference_object_maps: [%{reference | parent_resource: :Order}]}

    assert {:error, refusals} = Mapping.validate(mapping)
    assert [refusal] = Enum.filter(refusals, &(&1.code == :REFUSED_INVALID_JOIN_CONDITION))
    assert refusal.evidence.side == :parent
  end
end
