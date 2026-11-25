# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.TemporalDoctestTest do
  use ExUnit.Case, async: true

  doctest AshR2RML.Temporal

  test "predicates are the OWL-Time begin/end IRIs" do
    assert AshR2RML.Temporal.has_beginning() == "http://www.w3.org/2006/time#hasBeginning"
    assert AshR2RML.Temporal.has_end() == "http://www.w3.org/2006/time#hasEnd"
  end

  test "compile refuses an entry with neither bound" do
    entry = %AshR2RML.Dsl.Temporal{}

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_TERM_MAP}} =
             AshR2RML.Temporal.compile(entry, fn _ -> :error end)
  end

  test "compile refuses a range-typed bound with a typed unsupported refusal" do
    entry = %AshR2RML.Dsl.Temporal{start_attribute: :valid_at}
    lookup = fn :valid_at -> {:ok, Ash.Type.Range, "valid_at"} end
    assert {:error, %AshR2RML.Refusal{code: :UNSUPPORTED_ASH_TYPE}} = AshR2RML.Temporal.compile(entry, lookup)
  end

  test "compile projects start and end datetime attributes to xsd:dateTime" do
    entry = %AshR2RML.Dsl.Temporal{start_attribute: :a, end_attribute: :b}
    lookup = fn name -> {:ok, Ash.Type.UtcDatetime, to_string(name)} end

    assert {:ok, [begin_map, end_map]} = AshR2RML.Temporal.compile(entry, lookup)
    assert begin_map.predicate_iri == AshR2RML.Temporal.has_beginning()
    assert end_map.predicate_iri == AshR2RML.Temporal.has_end()
    assert begin_map.object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#dateTime"
    assert end_map.object_map.value == "b"
  end

  test "compile refuses a date-only bound" do
    entry = %AshR2RML.Dsl.Temporal{end_attribute: :d}
    lookup = fn _ -> {:ok, Ash.Type.Date, "d"} end
    assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_TERM_MAP}} = AshR2RML.Temporal.compile(entry, lookup)
  end
end
