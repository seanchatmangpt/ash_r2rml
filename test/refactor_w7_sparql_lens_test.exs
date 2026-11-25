# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7SparqlLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.InMemory.GraphQuery

  test "GRAPH with a default-prefix name is planned, not silently ignored" do
    sparql = """
    PREFIX : <http://schema.org/>
    SELECT * WHERE { GRAPH :Thing { ?s ?p ?o } }
    """

    assert {:ok, %{kind: :iri, iri: iri}} = GraphQuery.plan(sparql)
    assert to_string(iri) == "http://schema.org/Thing"
  end

  test "GRAPH with a default-prefix name and no declaration is refused" do
    sparql = "SELECT * WHERE { GRAPH :Thing { ?s ?p ?o } }"

    assert {:error, _message, %{prefix: ""}} = GraphQuery.plan(sparql)
  end
end
