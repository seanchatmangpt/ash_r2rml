# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.JoinTableRefusalTest do
  use ExUnit.Case, async: true
  test "join-table many-to-many remains an explicit refusal" do
    assert File.read!("AGENTS.md") =~ "`:join_table` many-to-many shape is an explicit typed refusal"
  end
end
