# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilderModifierFixesTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Capability
  alias AshR2RML.QueryBuilder.Modifiers

  @base "SELECT ?n WHERE { ?s ?p ?n } "

  describe "Modifiers.check/1" do
    test "refuses unparsed ORDER BY expression combined with LIMIT" do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               Modifiers.check(@base <> "ORDER BY (?n) LIMIT 3")

      assert {:error, %AshR2RML.Refusal{}} = Modifiers.check(@base <> "ORDER BY STR(?n) OFFSET 1")
      assert {:error, %AshR2RML.Refusal{}} = Modifiers.check(@base <> "GROUP BY ?n LIMIT 1")
    end

    test "accepts parsed modifiers, unparsed tails without LIMIT/OFFSET, and no tail" do
      assert :ok = Modifiers.check(@base <> "ORDER BY DESC(?n) LIMIT 3 OFFSET 1")
      assert :ok = Modifiers.check(@base <> "LIMIT 3")
      assert :ok = Modifiers.check(@base <> "ORDER BY STR(?n)")
      assert :ok = Modifiers.check(@base)
    end

    test "a LIMIT inside a string literal in the pattern is not a tail" do
      assert :ok = Modifiers.check(~s[SELECT ?n WHERE { ?s ?p "LIMIT" } ORDER BY STR(?n)])
    end
  end

  describe "Modifiers.compare/2 on temporal values and decimals" do
    test "dates sort chronologically, not by inspect" do
      assert Modifiers.compare(~D[2024-01-09], ~D[2024-01-10]) == :lt
      assert Modifiers.compare(~D[2025-01-01], ~D[2024-12-31]) == :gt
    end

    test "times, datetimes, naive datetimes" do
      assert Modifiers.compare(~T[09:00:00], ~T[10:00:00]) == :lt
      assert Modifiers.compare(~U[2024-05-01 10:00:00Z], ~U[2024-05-01 09:00:00Z]) == :gt
      assert Modifiers.compare(~N[2024-05-01 09:00:00], ~N[2024-05-01 10:00:00]) == :lt
    end

    test "decimals compare numerically and IRIs sort before literals" do
      assert Modifiers.compare(Decimal.new("9.5"), Decimal.new("10.0")) == :lt
      assert Modifiers.compare(RDF.iri("http://example.com/a"), 1) == :lt
      assert Modifiers.compare("a", "b") == :lt
    end

    test "run/2 orders dates chronologically" do
      rows = [%{"d" => ~D[2024-10-01]}, %{"d" => ~D[2024-02-01]}, %{"d" => ~D[2023-12-31]}]
      parsed = {:ok, %{order: [{"d", :asc}], limit: nil, offset: 0}}

      assert Enum.map(Modifiers.run(rows, parsed), & &1["d"]) ==
               [~D[2023-12-31], ~D[2024-02-01], ~D[2024-10-01]]
    end
  end

  describe "Capability.decimal_layer?/1" do
    test "ETS and Postgres push decimals; SQLite and others do not" do
      assert Capability.decimal_layer?(Ash.DataLayer.Ets)
      assert Capability.decimal_layer?(Module.concat(["AshPostgres", "DataLayer"]))
      refute Capability.decimal_layer?(Module.concat(["AshSqlite", "DataLayer"]))
      refute Capability.decimal_layer?(nil)
      refute Capability.decimal_layer?(Ash.DataLayer.Simple)
    end
  end
end
