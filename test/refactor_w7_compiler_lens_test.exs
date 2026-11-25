# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7CompilerLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{CompilationReceipt, Compiler, Refusal}

  test "compile(nil) is refused instead of yielding an empty bundle" do
    assert {:error, %Refusal{code: :REFUSED_INVALID_OPTION}} = Compiler.compile(nil)
  end

  test "validate(nil) yields a REFUSED receipt" do
    assert %CompilationReceipt{status: :REFUSED, refusals: [%Refusal{}]} = AshR2RML.validate(nil)
  end
end
