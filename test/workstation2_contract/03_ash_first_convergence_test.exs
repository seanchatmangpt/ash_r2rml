# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.AshFirstConvergenceTest do
  use ExUnit.Case, async: true
  test "Ash-first workflow converges on admitted semantic subject" do
    c = File.read!("AGENTS.md")
    assert c =~ "Ash-first and ontology-first workflows must converge on the same admitted semantic subject"
  end
end
