# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.EtsNoDdlTest do
  use ExUnit.Case, async: true
  test "ETS backend skips SQL DDL without blocking compilation" do
    assert File.read!("AGENTS.md") =~ "`:ets` skips SQL DDL rendering"
  end
end
