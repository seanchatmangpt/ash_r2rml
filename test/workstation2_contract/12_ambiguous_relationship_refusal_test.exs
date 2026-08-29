# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.AmbiguousRelationshipRefusalTest do
  use ExUnit.Case, async: true
  test "ambiguous relationship has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_AMBIGUOUS_RELATIONSHIP"
  end
end
