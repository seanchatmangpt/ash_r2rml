# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SubjectCodecPerfShapeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.Subject

  defp mapping(template) do
    %Resource{
      ash_resource: "Person",
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: template}
    }
  end

  test "repeated round trips are stable and the parsed template is cached" do
    template = "http://ex.org/perf/{id}/x/{name}"
    m = mapping(template)

    for _ <- 1..3 do
      assert {:ok, iri} = Subject.to_iri(m, %{id: "a b", name: "n"})
      assert iri == "http://ex.org/perf/a%20b/x/n"
      assert {:ok, %{id: "a b", name: "n"}} = Subject.from_iri(m, iri)
    end

    assert [{:lit, "http://ex.org/perf/"}, {:field, :id}, {:lit, "/x/"}, {:field, :name}] =
             :persistent_term.get({Subject, :segments, template})
  end

  test "refusals are not cached and stay identical" do
    m = mapping("http://ex.org/{zz_never_an_atom_qq9}")

    for _ <- 1..2 do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_TERM_MAP}} =
               Subject.to_iri(m, %{id: 1})
    end

    assert :persistent_term.get({Subject, :segments, "http://ex.org/{zz_never_an_atom_qq9}"}, nil) ==
             nil
  end
end
