# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SparqlIngestionTest do
  use ExUnit.Case, async: true

  alias RDF.NS.{FOAF, RDF}

  @query_string """
  PREFIX schema: <https://schema.org/>

  SELECT ?person ?name WHERE {
    ?person a schema:Person ;
            schema:name ?name .
  }
  """

  test "admits SPARQL query from raw Elixir string" do
    assert {:ok, query} = AshR2RML.admit_sparql(@query_string)
    assert query.form == :select
    assert is_binary(query.sha256)
    assert query.source == @query_string
  end

  test "admits SPARQL query constructed programmatically via SPARQL.Query" do
    parsed_query = SPARQL.Query.new(@query_string)

    assert {:ok, query} = AshR2RML.admit_sparql(parsed_query)
    assert query.form == :select
    assert is_binary(query.sha256)
  end

  test "loads and admits SPARQL .rq query file from disk" do
    tmp_path = Path.join(System.tmp_dir!(), "test_query_#{System.unique_integer([:positive])}.rq")
    File.write!(tmp_path, @query_string)

    on_exit(fn -> File.rm(tmp_path) end)

    assert {:ok, query} = AshR2RML.load_sparql_file(tmp_path)
    assert query.form == :select
    assert query.source == @query_string
  end

  test "returns typed refusal when loading non-existent file from disk" do
    assert {:error, refusal} = AshR2RML.load_sparql_file("/non/existent/path/query.rq")
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.detail =~ "failed to read SPARQL file from disk"
  end
end
