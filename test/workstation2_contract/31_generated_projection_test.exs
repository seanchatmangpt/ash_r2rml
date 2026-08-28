# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.GeneratedProjectionTest do
  use ExUnit.Case, async: true
  test "generated artifacts remain projections" do
    assert File.read!("AGENTS.md") =~ "Generated artifacts are projections"
  end
end
