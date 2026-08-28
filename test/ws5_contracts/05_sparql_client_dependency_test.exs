defmodule AshR2RML.WS5.SPARQLClientDependencyTest do
  use ExUnit.Case, async: true

  test "remote SPARQL client support remains available" do
    assert File.read!("mix.exs") =~ ~s({:sparql_client, "~> 0.5.1"})
  end
end
