# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.RelationshipPredicateRefusalTest do
  use ExUnit.Case, async: true
  test "relationship without predicate has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_RELATIONSHIP_WITHOUT_PREDICATE"
  end
end
