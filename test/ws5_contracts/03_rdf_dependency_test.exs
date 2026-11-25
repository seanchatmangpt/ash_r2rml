defmodule AshR2RML.WS5.RDFDependencyTest do
  use ExUnit.Case, async: true

  test "RDF 3.x is resolved and builds and serializes a real graph" do
    {:ok, applications} = :application.get_key(:ash_r2rml, :applications)
    assert :rdf in applications

    {:ok, vsn} = :application.get_key(:rdf, :vsn)
    assert {:ok, %Version{major: 3}} = Version.parse(to_string(vsn))

    graph =
      RDF.Graph.new([
        {RDF.iri("http://schema.org/Person"), RDF.type(), RDF.iri("http://www.w3.org/2000/01/rdf-schema#Class")}
      ])

    assert RDF.Graph.triple_count(graph) == 1
    assert {:ok, ttl} = RDF.Turtle.write_string(graph)
    assert ttl =~ "schema.org/Person"
  end
end
