# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW6DslDiagnosticsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.Resource.Verify

  test "diagnostic carries module, path, code and evidence" do
    refusal =
      Refusal.new(:REFUSED_UNKNOWN_ATTRIBUTE, {Some.Resource, :nope}, "unknown attribute", %{
        attribute: :nope
      })

    error = Verify.diagnostic(Some.Resource, [refusal])

    assert %Spark.Error.DslError{module: Some.Resource, path: [:r2rml]} = error
    assert error.message =~ "REFUSED_UNKNOWN_ATTRIBUTE"
    assert error.message =~ "unknown attribute"
    assert error.message =~ ":nope"
  end

  test "diagnostic joins multiple refusals and omits empty evidence" do
    refusals = [
      Refusal.new(:REFUSED_INVALID_TERM_MAP, :a, "first"),
      Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, :b, "second")
    ]

    message = Verify.diagnostic(Some.Resource, refusals).message

    assert message == "REFUSED_INVALID_TERM_MAP: first; REFUSED_MISSING_SUBJECT_MAP: second"
  end
end
