# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ErrorTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{Error, Refusal}

  doctest AshR2RML.Error

  @codes ~w(REFUSED_INVALID_CLASS_IRI REFUSED_MISSING_SUBJECT_MAP
    REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY REFUSED_UNMAPPED_DATATYPE
    REFUSED_AMBIGUOUS_RELATIONSHIP REFUSED_INVALID_JOIN_CONDITION
    REFUSED_RELATIONSHIP_WITHOUT_PREDICATE REFUSED_R2RML_JOIN_WITHOUT_IDENTITY
    REFUSED_UNPROVEN_EQUIVALENCE REFUSED_UNSUPPORTED_SPARQL_FEATURE
    REFUSED_RESULT_LIMIT_EXCEEDED REFUSED_TRIPLE_LIMIT_EXCEEDED
    REFUSED_MEMORY_LIMIT_EXCEEDED REFUSED_QUERY_TIMEOUT REFUSED_MISSING_TENANT
    REFUSED_MISSING_SUBJECT_KEY REFUSED_UNAUTHORIZED REFUSED_INVALID_SUBJECT_IRI
    REFUSED_NON_INVERTIBLE_TEMPLATE UNSUPPORTED_TERM_TYPE UNSUPPORTED_ASH_TYPE)a

  test "covers 21 codes" do
    assert length(@codes) == 21
  end

  for code <- @codes do
    test "new/2 #{code}: message and machine fields" do
      code = unquote(code)

      e =
        Error.new(code,
          resource: Some.Resource,
          field: :name,
          sparql_clause: "FILTER",
          details: %{k: 1}
        )

      msg = Exception.message(e)
      assert msg =~ Atom.to_string(code)
      assert msg =~ "Some.Resource"
      assert msg =~ ":name"
      assert msg =~ "FILTER"
      assert msg =~ "Hint: "
      assert e.code == code
      assert e.resource == Some.Resource
      assert e.field == :name
      assert e.sparql_clause == "FILTER"
      assert is_binary(e.hint) and e.hint != ""
      assert e.details == %{k: 1}
      assert e.message == msg
    end

    test "from_refusal/1 #{code}: tuple subject" do
      code = unquote(code)

      r =
        Refusal.new(code, {Some.Resource, :name}, "bad thing", %{
          sparql_clause: "OPTIONAL",
          extra: 2
        })

      e = Error.from_refusal(r)
      assert e.code == code
      assert e.resource == Some.Resource
      assert e.field == :name
      assert e.sparql_clause == "OPTIONAL"
      assert is_binary(e.hint) and e.hint != ""
      assert e.details.detail == "bad thing"
      assert e.details.subject == {Some.Resource, :name}
      assert e.details.extra == 2
      msg = Exception.message(e)
      assert msg =~ Atom.to_string(code)
      assert msg =~ "Some.Resource"
      assert msg =~ ":name"
      assert msg =~ "OPTIONAL"
      assert msg =~ "bad thing"
      assert msg =~ "Hint: "
    end
  end

  test "from_refusal with module subject and evidence overrides" do
    r =
      Refusal.new(:REFUSED_QUERY_TIMEOUT, Some.Resource, "slow", %{
        field: :age,
        clause: "ORDER BY",
        hint: "custom"
      })

    e = Error.from_refusal(r)
    assert e.resource == Some.Resource
    assert e.field == :age
    assert e.sparql_clause == "ORDER BY"
    assert e.hint == "custom"
    assert Exception.message(e) =~ "Hint: custom"
  end

  test "from_refusal with opaque subject leaves resource nil" do
    e = Error.from_refusal(Refusal.new(:REFUSED_UNAUTHORIZED, "x", "no"))
    assert e.resource == nil
    assert e.field == nil
    assert e.sparql_clause == nil
  end

  test "unknown code still yields a message" do
    e = Error.new(:REFUSED_SOMETHING_NEW)
    assert Exception.message(e) =~ "REFUSED_SOMETHING_NEW"
    assert e.hint == nil
  end

  test "is raisable" do
    assert_raise Error, ~r/REFUSED_MISSING_TENANT/, fn ->
      raise Error.new(:REFUSED_MISSING_TENANT)
    end
  end
end
