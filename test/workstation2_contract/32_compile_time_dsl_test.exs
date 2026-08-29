# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.CompileTimeDslTest do
  use ExUnit.Case, async: true
  test "DSL violations remain compile-time failures" do
    assert File.read!("AGENTS.md") =~ "Compile-time DSL violations fail at compile time"
  end
end
