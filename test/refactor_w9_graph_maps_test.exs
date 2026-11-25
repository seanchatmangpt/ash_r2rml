# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9GraphMapsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{GraphMap, LogicalTable, Resource, SubjectMap}

  defp mapping(graph_maps) do
    %Resource{
      ash_resource: "Thing",
      class_iris: ["http://schema.org/Thing"],
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
      identities: [[:id]],
      predicate_object_maps: [],
      reference_object_maps: [],
      graph_maps: graph_maps,
      metadata: %{attribute_columns: %{id: "id", name: "name"}}
    }
  end

  defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)
  defp codes(:ok), do: []

  test "column graph map naming an unmapped column is refused" do
    gm = [%GraphMap{strategy: :column, value: "ghost"}]
    assert :REFUSED_INVALID_GRAPH_MAP in codes(Mapping.validate(mapping(gm)))
  end

  test "template graph map with an unavailable field is refused" do
    gm = [%GraphMap{strategy: :template, value: "http://schema.org/g/{ghost}"}]
    assert :REFUSED_INVALID_GRAPH_MAP in codes(Mapping.validate(mapping(gm)))
  end

  test "controls: mapped column and mapped template field validate" do
    assert :ok = Mapping.validate(mapping([%GraphMap{strategy: :column, value: "name"}]))

    gm = [%GraphMap{strategy: :template, value: "http://schema.org/g/{id}"}]
    assert :ok = Mapping.validate(mapping(gm))
  end
end
