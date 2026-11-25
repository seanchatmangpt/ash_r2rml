# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11ColumnDanglingTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  defp mapping(column, metadata) do
    %Resource{
      ash_resource: "Thing",
      class_iris: ["http://schema.org/Thing"],
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
      identities: [[:id]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: "http://schema.org/name",
          object_map: %ObjectMap{strategy: :column, value: column}
        }
      ],
      reference_object_maps: [],
      metadata: metadata
    }
  end

  defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)
  defp codes(:ok), do: []

  test "column object map absent from declared attribute_columns is refused" do
    result = Mapping.validate(mapping("ghost", %{attribute_columns: %{id: "id", name: "name"}}))
    assert :REFUSED_INVALID_TERM_MAP in codes(result)
  end

  test "controls: declared column validates; undeclared metadata is not enforced" do
    assert :ok = Mapping.validate(mapping("name", %{attribute_columns: %{id: "id", name: "name"}}))
    assert :ok = Mapping.validate(mapping("ghost", %{}))
  end
end
