defmodule AshR2RML.WS5.SPARQLContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "SPARQL query dependency remains ~> 0.3.12" do
    assert @manifest =~ ~s({:sparql, "~> 0.3.12"})
  end
end
