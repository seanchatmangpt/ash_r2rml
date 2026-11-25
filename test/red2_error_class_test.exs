# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2ErrorClassTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Error
  alias AshR2RML.OBDA

  test "Ash classifies a REFUSED_UNAUTHORIZED error as forbidden" do
    err = Error.new(:REFUSED_UNAUTHORIZED)
    assert err.class == :forbidden

    class = Ash.Error.to_error_class(err)
    assert %Ash.Error.Forbidden{} = class
  end

  test "Ash classifies an invalid-class refusal as invalid" do
    class = Ash.Error.to_error_class(Error.new(:REFUSED_INVALID_CLASS_IRI))
    assert %Ash.Error.Invalid{} = class
  end

  test "OBDA classifies an Error with class :forbidden as REFUSED_UNAUTHORIZED" do
    failure = %Error{code: :REFUSED_READ_FAILED, class: :forbidden, details: %{}}
    assert {:REFUSED_UNAUTHORIZED, _} = OBDA.classify(failure)
  end

  test "OBDA classifies an Error nested in .errors with class :forbidden" do
    inner = %Error{code: :REFUSED_READ_FAILED, class: :forbidden, details: %{}}
    outer = %Error{code: :REFUSED_READ_FAILED, class: :invalid, details: %{}, message: "x"}
    outer = Map.put(outer, :errors, [inner])
    assert {:REFUSED_UNAUTHORIZED, _} = OBDA.classify(outer)
  end

  test "OBDA keeps REFUSED_READ_FAILED for a non-forbidden Error" do
    failure = %Error{code: :REFUSED_QUERY_TIMEOUT, class: :invalid, details: %{}}
    assert {:REFUSED_READ_FAILED, _} = OBDA.classify(failure)
  end

  test "Exception.message includes the code without a caller message" do
    msg = Exception.message(Error.new(:REFUSED_QUERY_TIMEOUT))
    assert msg =~ "REFUSED_QUERY_TIMEOUT"
  end

  test "Exception.message includes the code when a caller message is given" do
    err = Error.new(:REFUSED_QUERY_TIMEOUT, message: "custom text")
    msg = Exception.message(err)
    assert msg =~ "REFUSED_QUERY_TIMEOUT"
    assert msg =~ "custom text"
  end

  test "Exception.message of a bare struct includes the code" do
    assert Exception.message(%Error{code: :REFUSED_UNAUTHORIZED}) =~ "REFUSED_UNAUTHORIZED"
  end

  test "Error.new with :message keeps the code and hint on the struct" do
    err = Error.new(:REFUSED_QUERY_TIMEOUT, message: "custom text", hint: "do x")
    assert err.code == :REFUSED_QUERY_TIMEOUT
    assert err.hint == "do x"
    assert Exception.message(err) =~ "do x"
  end
end
