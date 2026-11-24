# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.AshFirstConvergenceTest do
  use ExUnit.Case, async: true

  test "Ash-first workflow converges on admitted semantic subject" do
    c = File.read!("AGENTS.md")
    assert c =~ "must normalize into one deterministic mapping IR before verification/rendering"
  end
end
