# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQLProtocolHardeningTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Local, Protocol}

  @query "SELECT * WHERE { ?s ?p ?o }"

  for endpoint <- [
        "file:///etc/passwd",
        "ftp://example.org/sparql",
        "gopher://example.org/",
        "http://",
        "https:///sparql",
        "not a url",
        ""
      ] do
    test "Protocol.query refuses endpoint #{inspect(endpoint)}" do
      assert {:error, %Refusal{}} = Protocol.query(unquote(endpoint), @query)
    end
  end

  defp graph(n) do
    Enum.reduce(1..n, RDF.Graph.new(), fn i, g ->
      RDF.Graph.add(g, {RDF.iri("https://example.org/s#{i}"), RDF.iri("https://example.org/p"), RDF.literal(i)})
    end)
  end

  test "Local.query under :max_rows returns all rows" do
    assert {:ok, obs} = Local.query(graph(3), @query, max_rows: 10)
    assert length(obs.rows) == 3
  end

  test "Local.query over :max_rows refuses with REFUSED_RESOURCE_BOUND" do
    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = Local.query(graph(3), @query, max_rows: 2)
  end
end
