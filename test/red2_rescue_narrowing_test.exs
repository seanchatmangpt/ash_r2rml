# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2RescueNarrowingTest do
  use ExUnit.Case, async: true

  alias AshR2RML.QueryBuilder.Pushdown
  alias AshR2RML.QueryBuilder.Verification
  alias AshR2RML.SPARQL.Result

  @root Path.expand("..", __DIR__)

  defp source(rel), do: @root |> Path.join(rel) |> File.read!()

  defp slice(text, from, to) do
    [_, rest] = String.split(text, from, parts: 2)
    [body | _] = String.split(rest, to, parts: 2)
    body
  end

  describe "Verification.verify/3 rescue scope" do
    test "verify/3 does not wrap root_key_rows/decide in a rescue" do
      body =
        slice(
          source("lib/ash_r2rml/query_builder/verification.ex"),
          "def verify(%Pushdown{keys: keys",
          "defp decide"
        )

      refute body =~ "rescue",
             "a bug inside root_key_rows/decide must crash loudly, not become :fallback"
    end

    test "unlimited pushdown is still :ok" do
      pushdown = %Pushdown{resource: nil, mapping: nil, plan: nil, fetch: nil}
      assert Verification.verify(pushdown, RDF.Graph.new(), 0) == :ok
    end
  end

  describe "SPARQL.Result.normalize/1" do
    test "non-RDF input yields a typed refusal" do
      assert {:error, %AshR2RML.Refusal{} = refusal} = Result.normalize(:not_rdf)
      assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    end

    test "normalize/1 decides RDF-ness by protocol lookup, not by rescuing UndefinedError" do
      body =
        slice(
          source("lib/ash_r2rml/sparql.ex"),
          "def normalize(data) do",
          "@doc \"SHA-256"
        )

      refute body =~ "Protocol.UndefinedError"
      assert body =~ "impl_for"
    end
  end

  describe "SPARQL.Local execute rescue scope" do
    test "execute/2 does not rescue FunctionClauseError (moduledoc contract)" do
      text = source("lib/ash_r2rml/sparql/local.ex")
      body = slice(text, "defp execute(data, admitted) do", "defp observe")

      refute body =~ "FunctionClauseError"
    end
  end
end
