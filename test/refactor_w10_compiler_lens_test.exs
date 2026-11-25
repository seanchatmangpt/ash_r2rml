# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW10CompilerLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{Compiler, Refusal}

  test "a non-module element in the resource list is a typed refusal, not a crash" do
    assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP}} =
             Compiler.compile([{:not, "a module"}])

    assert {:error, %Refusal{code: :REFUSED_MISSING_SUBJECT_MAP}} = Compiler.compile(["text"])
  end
end
