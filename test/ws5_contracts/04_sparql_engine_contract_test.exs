defmodule AshR2RML.WS5.SparqlEngineContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "SPARQL execution keeps the admitted 0.3.12 engine contract" do
    assert @mix =~ ~s({:sparql, "~> 0.3.12"})
  end
end
