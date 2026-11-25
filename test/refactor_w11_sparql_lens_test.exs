# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW11SparqlLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.InMemory.GraphQuery

  @graph "urn:uuid:5f1c2a64-0000-4000-8000-000000000001"

  test "an unclosed outer WHERE group is refused, not planned" do
    sparql = "SELECT * WHERE { GRAPH <#{@graph}> { ?s ?p ?o }"

    assert {:error, message, _evidence} = GraphQuery.plan(sparql)
    assert message =~ "unbalanced"
  end

  test "an unclosed FILTER paren beside a GRAPH pattern does not raise" do
    sparql = "SELECT * WHERE { GRAPH <#{@graph}> { ?s ?p ?o } FILTER ( ?s "

    assert {:error, _message, _evidence} = GraphQuery.plan(sparql)
  end

  test "a balanced GRAPH query still plans" do
    sparql = "SELECT * WHERE { GRAPH <#{@graph}> { ?s ?p ?o } }"

    assert {:ok, %{kind: :iri}} = GraphQuery.plan(sparql)
  end
end
