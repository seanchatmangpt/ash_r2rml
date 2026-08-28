defmodule AshR2RML.WS5.RDFContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "RDF semantic dependency remains on 3.x" do
    assert @manifest =~ ~s({:rdf, "~> 3.0"})
  end
end
