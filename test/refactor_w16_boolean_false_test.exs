# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW16BooleanFalseTest do
  use ExUnit.Case, async: true

  alias AshR2RML.SPARQL.Local

  @s "http://schema.org/"

  defp rows_for(value) do
    graph = RDF.Graph.new([{RDF.iri(@s <> "a"), RDF.iri(@s <> "p"), value}])

    assert {:ok, observation} = Local.query(graph, "SELECT ?o WHERE { ?s ?p ?o }")
    Enum.map(observation.rows, & &1["o"])
  end

  test "xsd:boolean false stays the boolean false, not the string \"false\"" do
    assert rows_for(RDF.XSD.Boolean.new(false)) == [false]
  end

  test "xsd:boolean true and a zero integer keep their native values" do
    assert rows_for(RDF.XSD.Boolean.new(true)) == [true]
    assert rows_for(RDF.XSD.Integer.new(0)) == [0]
  end
end
