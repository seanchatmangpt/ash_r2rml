# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.RuntimeRefusalShapeTest do
  use ExUnit.Case, async: true
  test "runtime APIs retain structured Refusal errors" do
    assert File.read!("AGENTS.md") =~ "{:error, %AshR2RML.Refusal{}}"
  end
end
