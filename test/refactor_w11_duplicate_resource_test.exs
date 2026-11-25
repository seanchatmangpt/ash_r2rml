# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11DuplicateResourceTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Bundle, LogicalTable, Resource, SubjectMap}

  defp resource(name, table, class) do
    %Resource{
      ash_resource: name,
      logical_table: %LogicalTable{table_name: table},
      subject_map: %SubjectMap{strategy: :template, value: "http://schema.org/#{table}/{id}"},
      identities: [["id"]],
      class_iris: [class]
    }
  end

  test "two entries for one ash_resource are refused" do
    a1 = resource("W11Dup", "w11_a", "http://schema.org/Thing")
    a2 = resource("W11Dup", "w11_b", "http://schema.org/Person")

    assert {:error, refusals} = Mapping.validate(%Bundle{resources: [a1, a2]})
    dup = Enum.filter(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
    assert [%{subject: "W11Dup"}] = dup
  end

  test "distinct ash_resources stay valid" do
    a = resource("W11A", "w11_a", "http://schema.org/Thing")
    b = resource("W11B", "w11_b", "http://schema.org/Person")

    assert :ok = Mapping.validate(%Bundle{resources: [a, b]})
  end
end
