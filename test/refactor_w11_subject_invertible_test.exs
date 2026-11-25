# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11SubjectInvertibleTest do
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

  for template <- ["http://schema.org/{id}-v1", "http://schema.org/{id}.json"] do
    @template template

    test "to_iri round-trips or refuses for #{template}" do
      m = mapping(@template)

      for key <- ["abc", "a b", "x-v1", "x.json", "x-v1-v1", "x.json.json", "v1"] do
        case Subject.to_iri(m, %{id: key}) do
          {:ok, iri} -> assert Subject.from_iri(m, iri) == {:ok, %{id: key}}
          {:error, %Refusal{code: code}} -> assert code == :REFUSED_INVALID_SUBJECT_IRI
        end
      end
    end
  end

  test "keys ending in the template's trailing literal are refused" do
    assert {:error, %Refusal{code: :REFUSED_INVALID_SUBJECT_IRI}} =
             Subject.to_iri(mapping("http://schema.org/{id}-v1"), %{id: "x-v1"})

    assert {:error, %Refusal{code: :REFUSED_INVALID_SUBJECT_IRI}} =
             Subject.to_iri(mapping("http://schema.org/{id}.json"), %{id: "x.json"})
  end

  test "ordinary keys still succeed" do
    assert {:ok, "http://schema.org/abc-v1"} = Subject.to_iri(mapping("http://schema.org/{id}-v1"), %{id: "abc"})
    assert {:ok, "http://schema.org/a%20b.json"} = Subject.to_iri(mapping("http://schema.org/{id}.json"), %{id: "a b"})
  end
end
