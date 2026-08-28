defmodule AshR2RML.WS5.RdfVersionContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "RDF graph integration remains on RDF 3" do
    assert @mix =~ ~s({:rdf, "~> 3.0"})
  end
end
