defmodule AshR2RML.WS5.RDFDependencyTest do
  use ExUnit.Case, async: true

  test "RDF graph support remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:rdf, "~> 3.0"})
  end
end
