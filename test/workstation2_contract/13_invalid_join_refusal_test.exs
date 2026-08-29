# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.InvalidJoinRefusalTest do
  use ExUnit.Case, async: true
  test "invalid join condition has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_INVALID_JOIN_CONDITION"
  end
end
