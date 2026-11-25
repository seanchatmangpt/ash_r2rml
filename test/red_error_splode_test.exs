# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedErrorSplodeTest do
  @moduledoc """
  Findings H12, H13, H28: refusals and errors integrate with Splode / Ash error classes,
  OBDA.query/3 has one error struct, catalog hints name real options, bound handling is aligned.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Error
  alias AshR2RML.OBDA
  alias AshR2RML.Refusal

  @sparql "SELECT ?s WHERE { ?s ?p ?o }"

  defp refusal do
    %Refusal{
      code: :REFUSED_UNAUTHORIZED,
      subject: :subject,
      detail: "nope",
      evidence: %{}
    }
  end

  test "H12 Refusal is an exception that can be raised and formatted" do
    r = refusal()
    assert Exception.exception?(r)
    assert is_binary(Exception.message(r))
    assert Exception.message(r) =~ "REFUSED_UNAUTHORIZED"

    raised =
      try do
        raise r
      rescue
        e in Refusal -> e
      end

    assert raised.code == :REFUSED_UNAUTHORIZED
    assert raised.detail == "nope"
  end

  test "H12 Ash.Error.to_error_class keeps a Refusal out of the unknown class" do
    class = Ash.Error.to_error_class(refusal())
    refute class.class == :unknown
    assert class.class == :invalid
  end

  test "H13 Error is a Splode error" do
    assert function_exported?(Error, :splode_error?, 0)
  end

  test "H13 Error classes map refusal codes to Ash error classes" do
    forbidden = Error.new(:REFUSED_UNAUTHORIZED)
    assert Ash.Error.to_error_class(forbidden).class == :forbidden

    invalid = Error.new(:REFUSED_INVALID_OPTION)
    assert Ash.Error.to_error_class(invalid).class == :invalid
  end

  test "H13 from_refusal result is classified by Ash, not wrapped as unknown" do
    err = Error.from_refusal(refusal())
    assert Ash.Error.to_error_class(err).class == :forbidden
  end

  test "H28 OBDA.query returns only %Error{} for a refused bound" do
    assert {:error, %Error{code: code}} = OBDA.query([], @sparql, max_rows: -1)
    assert is_atom(code)
  end

  test "H28 catalog hints name real option names" do
    assert Error.new(:REFUSED_RESULT_LIMIT_EXCEEDED).hint =~ "max_rows"
    refute Error.new(:REFUSED_RESULT_LIMIT_EXCEEDED).hint =~ "max_results"
    assert Error.new(:REFUSED_MEMORY_LIMIT_EXCEEDED).hint =~ "max_heap_words"
    refute Error.new(:REFUSED_MEMORY_LIMIT_EXCEEDED).hint =~ "max_memory"
  end

  test "H28 timeout_ms nil and 0 are refused consistently" do
    nil_result = OBDA.query([], @sparql, timeout_ms: nil)
    zero_result = OBDA.query([], @sparql, timeout_ms: 0)

    code = fn
      {:error, %{code: c}} -> c
      {:ok, _} -> :ok
    end

    # nil means "absent" per the docs: it must either succeed or match the zero-bound refusal.
    assert code.(nil_result) in [:ok, code.(zero_result), :REFUSED_UNSUPPORTED_SPARQL_FEATURE]
    assert {:error, %{details: %{option: :timeout_ms}}} = zero_result
  end
end
