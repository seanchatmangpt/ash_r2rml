# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.TurtleNotEquivalenceTest do
  use ExUnit.Case, async: true
  test "rendered Turtle is not semantic-equivalence proof" do
    assert File.read!("AGENTS.md") =~ "emitted Turtle is not proven semantic equivalence"
  end
end
