# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.RoundTripRefusalTest do
  use ExUnit.Case, async: true
  test "failed semantic round trip has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_SEMANTIC_ROUND_TRIP"
  end
end
