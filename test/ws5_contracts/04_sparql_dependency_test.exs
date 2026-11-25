defmodule AshR2RML.WS5.SPARQLDependencyTest do
  use ExUnit.Case, async: true

  test "SPARQL is resolved and executes a real query over a real graph" do
    {:ok, applications} = :application.get_key(:ash_r2rml, :applications)
    assert :sparql in applications

    s = RDF.iri("http://schema.org/Person")
    p = RDF.iri("http://schema.org/name")
    graph = RDF.Graph.new([{s, p, RDF.literal("Ada")}])

    assert %SPARQL.Query.Result{results: [row]} =
             SPARQL.execute_query(graph, "SELECT ?n WHERE { ?s <http://schema.org/name> ?n }")

    assert to_string(RDF.Literal.value(row["n"])) == "Ada"
  end
end
