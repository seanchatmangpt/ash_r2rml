# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW10RendererBridgeTest do
  @moduledoc """
  many_to_many forward and inverse bridge subject maps emit the same graph maps as
  `render_subject`: resource-level graph maps followed by subject-level graph maps.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping

  @resource_graph "http://schema.org/ResourceGraph"
  @subject_graph "http://schema.org/SubjectGraph"

  defp resource(overrides) do
    struct!(
      %Mapping.Resource{
        ash_resource: BridgeSource,
        logical_table: %Mapping.LogicalTable{table_name: "sources"},
        class_iris: ["http://schema.org/Thing"],
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "urn:uuid:{id}",
          term_type: :iri,
          graph_maps: [%Mapping.GraphMap{strategy: :constant, value: @subject_graph}]
        },
        graph_maps: [%Mapping.GraphMap{strategy: :constant, value: @resource_graph}],
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      },
      overrides
    )
  end

  defp bundle do
    source =
      resource(
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :targets,
            predicate_iri: "http://schema.org/knows",
            inverse_predicate: "http://schema.org/knownBy",
            parent_resource: BridgeTarget,
            metadata: %{
              kind: :many_to_many,
              through_logical_table: %Mapping.LogicalTable{table_name: "links"},
              source_to_join: %Mapping.JoinCondition{child: "id", parent: "source_id"},
              join_to_destination: %Mapping.JoinCondition{child: "target_id", parent: "id"}
            }
          }
        ]
      )

    target =
      resource(
        ash_resource: BridgeTarget,
        logical_table: %Mapping.LogicalTable{table_name: "targets"}
      )

    %Mapping.Bundle{resources: [source, target]}
  end

  test "forward and inverse bridge subject maps carry resource and subject graph maps" do
    assert {:ok, turtle} = AshR2RML.R2RML.render(bundle())

    bridge_blocks =
      turtle
      |> String.split("\n\n")
      |> Enum.filter(&String.contains?(&1, "links"))

    assert length(bridge_blocks) == 2

    for block <- bridge_blocks do
      [_, subject_map | _] = String.split(block, "rr:subjectMap [ ")
      subject_map = subject_map |> String.split(" ] ;") |> hd()

      assert subject_map =~ "rr:graph <#{@resource_graph}>"
      assert subject_map =~ "rr:graph <#{@subject_graph}>"
    end
  end
end
