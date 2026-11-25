# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9NormalizeNilTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Bundle, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  defp subject_map do
    %SubjectMap{strategy: :template, value: "http://schema.org/thing/{id}"}
  end

  defp resource(opts) do
    struct!(
      Resource,
      Keyword.merge(
        [
          ash_resource: "W9Nil",
          logical_table: %LogicalTable{table_name: "w9_nil"},
          subject_map: subject_map(),
          identities: [["id"]],
          class_iris: ["http://schema.org/Thing"]
        ],
        opts
      )
    )
  end

  defp codes({:error, refusals}), do: Enum.map(refusals, & &1.code)

  test "nil subject map: normalize is total and bundle/resource return typed refusal" do
    res = resource(subject_map: nil)

    assert Mapping.normalize(res).subject_map == nil
    assert %Bundle{resources: [%Resource{subject_map: nil}]} = Mapping.normalize(%Bundle{resources: [res]})
    assert :REFUSED_MISSING_SUBJECT_MAP in codes(Mapping.validate(res))
    assert :REFUSED_MISSING_SUBJECT_MAP in codes(Mapping.validate(%Bundle{resources: [res]}))
  end

  test "nil object map: normalize is total and bundle/resource return typed refusal" do
    pom = %PredicateObjectMap{
      attribute: :name,
      predicate_iri: "http://schema.org/name",
      object_map: nil
    }

    res = resource(predicate_object_maps: [pom])

    assert [%PredicateObjectMap{object_map: nil}] = Mapping.normalize(res).predicate_object_maps
    assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(res))
    assert :REFUSED_INVALID_TERM_MAP in codes(Mapping.validate(%Bundle{resources: [res]}))
  end

  test "valid object map still normalizes" do
    object = %ObjectMap{strategy: :column, value: "name"}
    pom = %PredicateObjectMap{attribute: :name, predicate_iri: "http://schema.org/name", object_map: object}

    assert :ok = Mapping.validate(%Bundle{resources: [resource(predicate_object_maps: [pom])]})
  end
end
