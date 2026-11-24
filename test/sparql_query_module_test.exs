defmodule AshR2RML.SPARQLQueryModuleTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Query

  @select "SELECT ?s WHERE { ?s ?p ?o }"
  @ask "ASK { ?s ?p ?o }"

  defp sha(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  test "admit/1 of SELECT text records source, form, and lexical sha256" do
    assert {:ok, %Query{} = q} = Query.admit(@select)
    assert q.source == @select
    assert q.form == :select
    assert q.sha256 == sha(@select)
    assert %SPARQL.Query{} = q.parsed
  end

  test "admit/1 of ASK text yields :ask form" do
    assert {:ok, %Query{form: :ask}} = Query.admit(@ask)
  end

  test "identity is lexical: whitespace change changes sha256" do
    {:ok, a} = Query.admit(@select)
    {:ok, b} = Query.admit(@select <> " ")
    refute a.sha256 == b.sha256
  end

  test "admit/1 is idempotent on an admitted struct" do
    {:ok, q} = Query.admit(@select)
    assert {:ok, ^q} = Query.admit(q)
  end

  test "admit/1 accepts a parsed SPARQL.Query and keeps its query_string" do
    parsed = SPARQL.Query.new(@select)
    assert {:ok, %Query{} = q} = Query.admit(parsed)
    assert q.source == parsed.query_string
    assert q.sha256 == sha(parsed.query_string)
  end

  test "admit/1 refuses garbage text with a typed refusal" do
    assert {:error, %Refusal{}} = Query.admit("THIS IS NOT SPARQL {{{")
  end

  test "admit/1 refuses non-query terms" do
    assert {:error, %Refusal{}} = Query.admit(42)
    assert {:error, %Refusal{}} = Query.admit(nil)
  end

  test "load_file/1 admits a query read from disk" do
    path = Path.join(System.tmp_dir!(), "q_#{System.unique_integer([:positive])}.rq")
    File.write!(path, @select)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, %Query{source: @select, form: :select}} = Query.load_file(path)
  end

  test "load_file/1 refuses a missing file" do
    path = Path.join(System.tmp_dir!(), "missing_#{System.unique_integer([:positive])}.rq")
    assert {:error, %Refusal{}} = Query.load_file(path)
  end
end
