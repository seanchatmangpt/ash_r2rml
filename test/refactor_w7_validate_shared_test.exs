# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7ValidateSharedTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{GraphMap, LogicalTable, Resource, SubjectMap}
  alias AshR2RML.Mapping.Validate.{BundleRules, Shared}
  alias AshR2RML.Refusal

  @klass "http://schema.org/Person"

  defp resource(name, subject_map, extra \\ []) do
    struct!(
      %Resource{
        ash_resource: name,
        logical_table: %LogicalTable{table_name: "people"},
        subject_map: subject_map,
        class_iris: [@klass],
        identities: [[:id]]
      },
      extra
    )
  end

  defp blank(strategy, value), do: %SubjectMap{strategy: strategy, value: value, term_type: :blank_node}

  test "available_columns resolves identities through attribute_columns like identity_column_sets" do
    r = resource(A, %SubjectMap{strategy: :template, value: "http://schema.org/{person_id}"})
    r = %{r | metadata: %{attribute_columns: %{id: "person_id"}}}

    assert Mapping.identity_column_sets(r) == [["person_id"]]
    assert Shared.available_columns(r) == MapSet.new(["person_id"])
  end

  test "constant blank-node subject is not a stable identity" do
    refute Mapping.stable_subject_identity?(resource(A, blank(:constant, "b0")))
  end

  test "blank-node template must be backed by a declared identity" do
    assert Mapping.stable_subject_identity?(resource(A, blank(:blank_node, "b_{id}")))
    refute Mapping.stable_subject_identity?(resource(A, blank(:blank_node, "b_{name}")))
    refute Mapping.stable_subject_identity?(resource(A, blank(:template, "b_{id}_{name}")))
  end

  test "same table and template in different named graphs is a lawful, distinct contract" do
    subject = %SubjectMap{strategy: :template, value: "http://schema.org/p/{id}"}
    graph = fn v -> %SubjectMap{subject | graph_maps: [%GraphMap{strategy: :constant, value: v}]} end

    a = resource(A, graph.("http://schema.org/g1"))
    b = resource(B, graph.("http://schema.org/g2"))

    assert [] = BundleRules.duplicate_subject_contracts([a, b])

    assert [%Refusal{code: :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY}] =
             BundleRules.duplicate_subject_contracts([a, %{b | subject_map: a.subject_map}])
  end
end
