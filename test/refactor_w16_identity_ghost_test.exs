# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW16IdentityGhostTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.Refusal

  defp resource(overrides) do
    base = %Resource{
      ash_resource: "urn:uuid:00000000-0000-0000-0000-00000000000a",
      logical_table: %LogicalTable{table_name: "a"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}"},
      class_iris: ["http://schema.org/Person"],
      identities: [[:id]],
      metadata: %{attribute_columns: %{id: "id"}}
    }

    struct!(base, overrides)
  end

  test "valid declared identity column is accepted" do
    assert Mapping.validate(resource([])) == :ok
  end

  test "identity column absent from declared attribute_columns is refused" do
    ghost =
      resource(
        identities: [[:ghost]],
        subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{ghost}"}
      )

    assert {:error, [%Refusal{} | _]} = Mapping.validate(ghost)
  end

  test "undeclared metadata keeps identity columns available" do
    undeclared_meta =
      resource(
        identities: [[:ghost]],
        subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{ghost}"},
        metadata: %{}
      )

    assert Mapping.validate(undeclared_meta) == :ok
  end
end
