# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11BlankSubjectTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}

  defp mapping(subject_map) do
    %Resource{
      ash_resource: "Thing",
      class_iris: ["http://schema.org/Thing"],
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: subject_map,
      identities: [[:id]],
      predicate_object_maps: [],
      reference_object_maps: [],
      graph_maps: [],
      metadata: %{attribute_columns: %{id: "id"}}
    }
  end

  defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)
  defp codes(:ok), do: []

  test "constant blank-node subject is refused with REFUSED_INVALID_TERM_MAP" do
    subject = %SubjectMap{strategy: :constant, value: "b0", term_type: :blank_node}
    assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(mapping(subject)))
  end

  test "column blank-node subject stays lawful" do
    subject = %SubjectMap{strategy: :column, value: "id", term_type: :blank_node}
    refute :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(mapping(subject)))
  end

  test "template blank-node subject stays lawful" do
    subject = %SubjectMap{strategy: :blank_node, value: "b{id}", term_type: :blank_node}
    refute :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(mapping(subject)))
  end
end
