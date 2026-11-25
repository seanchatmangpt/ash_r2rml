# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11M2mDanglingTest do
  @moduledoc """
  many_to_many references refuse bridge columns that do not exist on the child or parent mapping.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping

  defp resource(overrides) do
    struct!(
      %Mapping.Resource{
        ash_resource: M2mSource,
        logical_table: %Mapping.LogicalTable{table_name: "sources"},
        class_iris: ["http://schema.org/Thing"],
        subject_map: %Mapping.SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      },
      overrides
    )
  end

  defp bundle(child_column, parent_column) do
    source =
      resource(
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :targets,
            predicate_iri: "http://schema.org/knows",
            parent_resource: M2mTarget,
            metadata: %{
              kind: :many_to_many,
              through_logical_table: %Mapping.LogicalTable{table_name: "links"},
              source_to_join: %Mapping.JoinCondition{child: child_column, parent: "source_id"},
              join_to_destination: %Mapping.JoinCondition{child: "target_id", parent: parent_column}
            }
          }
        ]
      )

    target = resource(ash_resource: M2mTarget, logical_table: %Mapping.LogicalTable{table_name: "targets"})
    %Mapping.Bundle{resources: [source, target]}
  end

  test "bridge columns present on both sides validate" do
    assert :ok = Mapping.validate(bundle("id", "id"))
  end

  test "bridge source column absent from the child is refused" do
    assert {:error, refusals} = Mapping.validate(bundle("missing_child", "id"))
    assert Enum.any?(refusals, &(&1.code == :REFUSED_INVALID_JOIN_CONDITION))
  end

  test "bridge destination column absent from the parent is refused" do
    assert {:error, refusals} = Mapping.validate(bundle("id", "missing_parent"))
    assert Enum.any?(refusals, &(&1.code == :REFUSED_INVALID_JOIN_CONDITION))
  end
end
