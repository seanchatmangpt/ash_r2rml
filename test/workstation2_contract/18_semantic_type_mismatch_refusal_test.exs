# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.SemanticTypeMismatchRefusalTest do
  use ExUnit.Case, async: true
  test "semantic type Ash mismatch has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_SEMANTIC_TYPE_ASH_MISMATCH"
  end
end
