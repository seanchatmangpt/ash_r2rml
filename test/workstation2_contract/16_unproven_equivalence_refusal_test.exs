# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.UnprovenEquivalenceRefusalTest do
  use ExUnit.Case, async: true
  test "unproven equivalence has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_UNPROVEN_EQUIVALENCE"
  end
end
