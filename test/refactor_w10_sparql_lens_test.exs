# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW10SparqlLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.InMemory.GraphQuery

  test "unbalanced GRAPH group is a typed refusal, not a crash" do
    sparql = "SELECT * WHERE { GRAPH <http://schema.org/g> { ?s ?p ?o "
    assert {:error, message, _evidence} = GraphQuery.plan(sparql)
    assert message =~ "unbalanced"
  end

  test "balanced GRAPH query still plans" do
    sparql = "SELECT * WHERE { GRAPH <http://schema.org/g> { ?s ?p ?o } }"
    assert {:ok, %{kind: :iri}} = GraphQuery.plan(sparql)
  end
end
