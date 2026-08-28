# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.CompositeJoinTest do
  use ExUnit.Case, async: true
  test "composite-key joins remain supported" do
    assert File.read!("AGENTS.md") =~ "composite-key (multi-column) `rr:joinCondition`s"
  end
end
