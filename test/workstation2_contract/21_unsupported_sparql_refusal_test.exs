# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.UnsupportedSparqlRefusalTest do
  use ExUnit.Case, async: true
  test "unsupported SPARQL feature has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_UNSUPPORTED_SPARQL_FEATURE"
  end
end
