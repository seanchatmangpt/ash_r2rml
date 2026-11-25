# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7TypesLensTest do
  use ExUnit.Case, async: true

  test "contract/1 answers :error for non-module input instead of crashing" do
    assert AshR2RML.Type.contract("not a module") == :error
    assert AshR2RML.Type.contract(nil) == :error
    assert AshR2RML.Type.contract(42) == :error
  end

  test "encode/2 and decode/2 return typed errors for non-module input" do
    assert AshR2RML.Type.encode("not a module", 1) == {:error, :not_semantic_type}
    assert AshR2RML.Type.decode(42, {:iri, "http://schema.org/Thing"}) == {:error, :not_semantic_type}
  end
end
