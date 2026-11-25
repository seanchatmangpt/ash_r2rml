# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9TemplateIriTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.Validate.{Properties, Subject}
  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  doctest AshR2RML.Mapping.Validate.Subject

  @predicate "http://schema.org/url"

  defp resource(subject_map, object_map \\ nil) do
    maps =
      case object_map do
        nil -> []
        object -> [%PredicateObjectMap{attribute: :id, predicate_iri: @predicate, object_map: object}]
      end

    %Resource{
      ash_resource: "Fixture",
      logical_table: %LogicalTable{table_name: "things"},
      subject_map: subject_map,
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: maps,
      metadata: %{attribute_columns: %{id: "id", x: "x"}}
    }
  end

  defp subject_defects(template, term_type \\ :iri) do
    %SubjectMap{strategy: :template, value: template, term_type: term_type}
    |> resource()
    |> Subject.subject()
    |> Enum.filter(&match?(%{evidence: %{defect: _}}, &1))
  end

  defp object_defects(template) do
    object = %ObjectMap{strategy: :template, value: template, term_type: :iri}

    %SubjectMap{strategy: :template, value: "http://schema.org/uuid/{id}"}
    |> resource(object)
    |> Properties.check()
    |> Enum.filter(&match?(%{evidence: %{defect: _}}, &1))
  end

  test "well-formed absolute subject template is accepted" do
    assert subject_defects("http://schema.org/uuid/{id}") == []
    assert subject_defects("http://schema.org/thing/{id}/{x}") == []
  end

  test "unbalanced braces in a subject template are refused" do
    for template <- ["http://schema.org/{id}/{x", "http://schema.org/x}/{id}", "http://schema.org/{{id}}"] do
      assert [%{code: :REFUSED_INVALID_TERM_MAP, evidence: %{defect: :unbalanced_braces}}] =
               subject_defects(template)
    end
  end

  test "relative or placeholder-leading subject template is refused" do
    for template <- ["things/{id}", "{id}", "/{id}"] do
      assert [%{code: :REFUSED_INVALID_TERM_MAP, evidence: %{defect: :not_absolute}}] =
               subject_defects(template)
    end
  end

  test "forbidden characters in literal parts are refused" do
    for template <- ["http://schema.org/a b/{id}", "http://schema.org/a<b>/{id}", "http://schema.org/{id}/a|b"] do
      assert [%{evidence: %{defect: :forbidden_character}}] = subject_defects(template)
    end
  end

  test "relative blank-node subject templates remain lawful" do
    assert subject_defects("node/{id}", :blank_node) == []
  end

  test "IRI object templates get the same refusals" do
    assert object_defects("http://schema.org/uuid/{id}") == []
    assert [%{evidence: %{defect: :unbalanced_braces}}] = object_defects("http://schema.org/{id}/{x")
    assert [%{evidence: %{defect: :not_absolute}}] = object_defects("rel/{id}")
    assert [%{evidence: %{defect: :forbidden_character}}] = object_defects("http://schema.org/a b/{id}")
  end

  test "literal object templates are not subject to IRI shape rules" do
    object = %ObjectMap{strategy: :template, value: "plain {id}", term_type: :literal}

    refusals =
      %SubjectMap{strategy: :template, value: "http://schema.org/uuid/{id}"}
      |> resource(object)
      |> Properties.check()

    assert refusals == []
  end
end
