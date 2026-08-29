# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ProjectionRequiredRefusalTest do
  use ExUnit.Case, async: true
  test "semantic type requiring resource projection has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_SEMANTIC_TYPE_REQUIRES_RESOURCE_PROJECTION"
  end
end
