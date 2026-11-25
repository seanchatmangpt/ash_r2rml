# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

require AshR2RML.DataLayerContract.Shapes, as: Shapes

Shapes.define(AshR2RML.RefactorW11ShapeCoverage.Layer, :ets)

defmodule AshR2RML.RefactorW11ShapeCoverageTest do
  @moduledoc """
  SPARQL shapes with no coverage on any other layer (COUNT / GROUP BY, ASK, MINUS, VALUES, BIND,
  subquery, property path, GRAPH), executed through `AshR2RML.OBDA.query/3` against real
  `Ash.DataLayer.Ets` rows.

  Each shape asserts one of exactly two outcomes: the correct typed result (checked against the
  seed data by an independent oracle) or the typed refusal `:REFUSED_UNSUPPORTED_SPARQL_FEATURE`.
  Any other outcome (another code, wrong rows) fails.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.DataLayerContract.Shapes

  @layer AshR2RML.RefactorW11ShapeCoverage.Layer
  @s "http://schema.org/"
  @refused :REFUSED_UNSUPPORTED_SPARQL_FEATURE

  setup do
    Shapes.reseed!(@layer)
    :ok
  end

  defp run(sparql) do
    opts = [domain: Shapes.domain(@layer), authorize?: false, allow_unauthorized: true]

    case AshR2RML.OBDA.query(Shapes.specs(@layer), sparql, opts) do
      {:ok, result} -> {:ok, Enum.map(result.bindings, &lexical_row/1)}
      {:error, %{code: code}} -> {:error, code}
    end
  end

  defp lexical_row(row), do: Map.new(row, fn {k, v} -> {k, lexical(v)} end)

  defp lexical(%RDF.Literal{} = literal), do: RDF.Literal.lexical(literal)
  defp lexical(value), do: to_string(value)

  # Either the correct typed result (sorted rows equal `expected`) or the typed refusal.
  defp assert_result_or_refusal(sparql, expected) do
    case run(sparql) do
      {:ok, rows} -> assert Enum.sort_by(rows, &inspect/1) == Enum.sort_by(expected, &inspect/1)
      {:error, code} -> assert code == @refused
    end
  end

  test "control: a plain SELECT answers and an unsupported ORDER BY expression is refused" do
    assert {:ok, rows} = run("SELECT ?name WHERE { ?s <#{@s}name> ?name . ?s a <#{@s}Person> }")
    assert rows |> Enum.map(& &1["name"]) |> Enum.sort() == ["Ada", "Bob", "Cy", "Di", "Ed"]

    assert {:error, @refused} =
             run("SELECT ?s ?name WHERE { ?s <#{@s}name> ?name } ORDER BY STR(?name) LIMIT 2")
  end

  test "ASK true for a present fact and false for an absent one" do
    for {name, expected} <- [{"Ada", "true"}, {"Nobody", "false"}] do
      case run(~s(ASK { ?s <#{@s}name> "#{name}" })) do
        {:ok, [row]} -> assert row |> Map.values() |> Enum.map(&String.downcase/1) == [expected]
        {:error, code} -> assert code == @refused
      end
    end
  end

  test "MINUS removes subjects that have an age" do
    assert_result_or_refusal(
      "SELECT ?name WHERE { ?s <#{@s}name> ?name . MINUS { ?s <#{@s}age> ?a } " <>
        "FILTER(?name != \"Acme\" && ?name != \"Plain Org\") }",
      [%{"name" => "Bob"}, %{"name" => "Ed"}]
    )
  end

  test "VALUES restricts a variable" do
    assert_result_or_refusal(
      ~s(SELECT ?name WHERE { VALUES ?name { "Ada" "Di" } ?s <#{@s}name> ?name }),
      [%{"name" => "Ada"}, %{"name" => "Di"}]
    )
  end

  test "BIND computes a projected expression" do
    assert_result_or_refusal(
      "SELECT ?name ?tag WHERE { ?s <#{@s}age> ?a ; <#{@s}name> ?name . BIND(UCASE(?name) AS ?tag) }",
      [
        %{"name" => "Ada", "tag" => "ADA"},
        %{"name" => "Cy", "tag" => "CY"},
        %{"name" => "Di", "tag" => "DI"}
      ]
    )
  end

  test "subquery" do
    assert_result_or_refusal(
      "SELECT ?name WHERE { { SELECT ?s WHERE { ?s <#{@s}age> ?a } } ?s <#{@s}name> ?name }",
      [%{"name" => "Ada"}, %{"name" => "Cy"}, %{"name" => "Di"}]
    )
  end

  test "property path: sequence across the reference join" do
    assert_result_or_refusal(
      "SELECT ?pname ?oname WHERE { ?s <#{@s}memberOf>/<#{@s}name> ?oname . ?s <#{@s}name> ?pname }",
      [
        %{"pname" => "Ada", "oname" => "Acme"},
        %{"pname" => "Bob", "oname" => "Plain Org"},
        %{"pname" => "Di", "oname" => "Acme"}
      ]
    )
  end

  test "property path: alternative" do
    assert_result_or_refusal(
      "SELECT ?v WHERE { <urn:uuid:p1> <#{@s}name>|<#{@s}age> ?v }",
      [%{"v" => "Ada"}, %{"v" => "36"}]
    )
  end

  test "GRAPH with a variable or an absent IRI sees no named graph (empty) or is refused" do
    for sparql <- [
          "SELECT ?g ?name WHERE { GRAPH ?g { ?s <#{@s}name> ?name } }",
          "SELECT ?name WHERE { GRAPH <#{@s}absentGraph> { ?s <#{@s}name> ?name } }"
        ] do
      assert_result_or_refusal(sparql, [])
    end
  end
end
