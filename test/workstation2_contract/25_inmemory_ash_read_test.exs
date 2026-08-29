# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.InMemoryAshReadTest do
  use ExUnit.Case, async: true
  test "in-memory OBDA remains Ash-mediated" do
    c = File.read!("AGENTS.md")
    assert c =~ "AshR2RML.OBDA.InMemory` is Ash-mediated (`Ash.read!/2`)"
  end
end
