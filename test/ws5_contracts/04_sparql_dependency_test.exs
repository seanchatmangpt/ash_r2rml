defmodule AshR2RML.WS5.SPARQLDependencyTest do
  use ExUnit.Case, async: true

  test "SPARQL execution remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:sparql, "~> 0.3.12"})
  end
end
