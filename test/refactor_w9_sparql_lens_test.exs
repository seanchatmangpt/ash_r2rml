# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9SparqlLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Local, Result}

  defp graph do
    RDF.Graph.new([
      {RDF.iri("http://schema.org/a"), RDF.iri("http://schema.org/name"), "A"},
      {RDF.iri("http://schema.org/b"), RDF.iri("http://schema.org/name"), "B"}
    ])
  end

  @select "SELECT ?s WHERE { ?s <http://schema.org/name> ?o }"

  test "invalid max_rows refuses instead of disabling the bound" do
    for bad <- [0, -1, nil, "5"] do
      assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} =
               Local.query(graph(), @select, max_rows: bad)
    end
  end

  test "valid max_rows still bounds and admits" do
    assert {:ok, %{rows: rows}} = Local.query(graph(), @select, max_rows: 2)
    assert length(rows) == 2
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Local.query(graph(), @select, max_rows: 1)
  end

  test "bound passes errors through" do
    assert {:error, :x} == Result.bound({:error, :x}, :s, 0)
  end
end
