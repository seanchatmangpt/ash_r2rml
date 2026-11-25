# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW12SubjectNonInvertibleTest do
  @moduledoc """
  Pins the documented collision risk: `to_iri/2` stays permissive for non-invertible templates
  (existing suites pin that), while `from_iri/2` refuses them.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.{Refusal, Subject}

  defp mapping(template) do
    %Resource{
      ash_resource: "Person",
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: template}
    }
  end

  test "adjacent placeholders: distinct keys collide on one IRI and from_iri refuses it" do
    m = mapping("http://schema.org/{a}{b}")

    assert {:ok, iri} = Subject.to_iri(m, %{a: "x", b: "yz"})
    assert Subject.to_iri(m, %{a: "xy", b: "z"}) == {:ok, iri}
    assert {:error, %Refusal{code: :REFUSED_NON_INVERTIBLE_TEMPLATE}} = Subject.from_iri(m, iri)
  end

  test "a reserved separator keeps the mapping injective" do
    m = mapping("http://schema.org/{a}/{b}")

    assert {:ok, one} = Subject.to_iri(m, %{a: "x", b: "yz"})
    assert {:ok, two} = Subject.to_iri(m, %{a: "xy", b: "z"})
    assert one != two
  end
end
