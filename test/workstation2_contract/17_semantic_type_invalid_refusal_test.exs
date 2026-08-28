# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.SemanticTypeInvalidRefusalTest do
  use ExUnit.Case, async: true
  test "invalid semantic type has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_SEMANTIC_TYPE_INVALID"
  end
end
