# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedRenderersTest do
  @moduledoc """
  Red-before-green courts for the renderer audit findings H07, H32 and H44.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Refusal

  @ref_graph "http://schema.org/ReferenceGraph"

  defp resource(overrides) do
    struct!(
      %Mapping.Resource{
        ash_resource: RedSource,
        logical_table: %Mapping.LogicalTable{table_name: "sources"},
        class_iris: ["http://schema.org/Thing"],
        subject_map: %Mapping.SubjectMap{
          strategy: :template,
          value: "urn:uuid:{id}",
          term_type: :iri
        },
        identities: [[:id]],
        metadata: %{attribute_columns: %{id: "id"}}
      },
      overrides
    )
  end

  defp m2m_metadata(overrides \\ %{}) do
    Map.merge(
      %{
        kind: :many_to_many,
        through_logical_table: %Mapping.LogicalTable{table_name: "links"},
        source_to_join: %Mapping.JoinCondition{child: "id", parent: "source_id"},
        join_to_destination: %Mapping.JoinCondition{child: "target_id", parent: "id"}
      },
      overrides
    )
  end

  defp m2m_bundle(metadata, graph_maps \\ []) do
    source =
      resource(
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :targets,
            predicate_iri: "http://schema.org/knows",
            inverse_predicate: "http://schema.org/knownBy",
            parent_resource: RedTarget,
            graph_maps: graph_maps,
            metadata: metadata
          }
        ]
      )

    target =
      resource(
        ash_resource: RedTarget,
        logical_table: %Mapping.LogicalTable{table_name: "targets"}
      )

    %Mapping.Bundle{resources: [source, target]}
  end

  defp plain_bundle(graph_maps) do
    source =
      resource(
        reference_object_maps: [
          %Mapping.ReferenceObjectMap{
            relationship: :target,
            predicate_iri: "http://schema.org/knows",
            inverse_predicate: "http://schema.org/knownBy",
            parent_resource: RedTarget,
            graph_maps: graph_maps,
            joins: [%Mapping.JoinCondition{child: "id", parent: "id"}]
          }
        ]
      )

    target =
      resource(
        ash_resource: RedTarget,
        logical_table: %Mapping.LogicalTable{table_name: "targets"}
      )

    %Mapping.Bundle{resources: [source, target]}
  end

  defp inverse_blocks(turtle) do
    turtle
    |> String.split("\n\n")
    |> Enum.filter(&String.contains?(&1, "knownBy"))
  end

  test "H07 render returns a flat binary and the first typed refusal for an unmapped parent" do
    assert {:ok, turtle} = AshR2RML.R2RML.render(m2m_bundle(m2m_metadata()))
    assert is_binary(turtle)
    refute turtle =~ "{:ok"

    orphan = %Mapping.Bundle{resources: [hd(m2m_bundle(m2m_metadata()).resources)]}
    assert {:error, [%Refusal{code: code} | _]} = AshR2RML.R2RML.render(orphan)
    assert code == :REFUSED_RELATIONSHIP_TARGET_UNMAPPED
  end

  test "H32 many_to_many inverse bridge map carries reference graph maps" do
    graph = %Mapping.GraphMap{strategy: :constant, value: @ref_graph}
    assert {:ok, turtle} = AshR2RML.R2RML.render(m2m_bundle(m2m_metadata(), [graph]))

    assert [block] = inverse_blocks(turtle)
    assert block =~ "rr:graph <#{@ref_graph}>"
  end

  test "H32 standard inverse map carries reference graph maps" do
    graph = %Mapping.GraphMap{strategy: :constant, value: @ref_graph}
    assert {:ok, turtle} = AshR2RML.R2RML.render(plain_bundle([graph]))

    assert [block] = inverse_blocks(turtle)
    assert block =~ "rr:graph <#{@ref_graph}>"
  end

  test "H44 nil bridge column is refused with a typed refusal, never rendered as empty" do
    metadata =
      m2m_metadata(%{
        source_parent_column: nil,
        source_join_column: "source_id",
        destination_parent_column: "id",
        destination_join_column: "target_id"
      })

    assert {:error, [%Refusal{} | _]} = AshR2RML.R2RML.render(m2m_bundle(metadata))
  end

  test "H44 empty through logical table is refused as REFUSED_INVALID_LOGICAL_TABLE" do
    metadata = m2m_metadata(%{through_logical_table: %Mapping.LogicalTable{}})

    assert {:error, %Refusal{code: :REFUSED_INVALID_LOGICAL_TABLE}} =
             AshR2RML.R2RML.render(m2m_bundle(metadata))
  end
end
