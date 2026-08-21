# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.SparqlDifferentialTest do
  use ExUnit.Case, async: true

  alias AshR2ML.SPARQL.{Differential, Observation}

  defp observation(strategy, rows, query_sha256 \\ "query-sha") do
    %Observation{
      strategy: strategy,
      query_sha256: query_sha256,
      query_form: :select,
      status: :PARTIAL_ALIVE,
      standing: :observed,
      evidence_kind: :test_fixture,
      rows: rows,
      result_kind: :bindings,
      result_sha256: AshR2ML.SPARQL.Result.hash_rows(rows)
    }
  end

  test "multi-engine differential is insensitive to observation and row ordering" do
    first = [
      %{"account" => "urn:a:1", "organization" => "urn:o:1"},
      %{"account" => "urn:a:2", "organization" => "urn:o:1"}
    ]

    second = Enum.reverse(first)

    observations = [
      observation(:protocol, first),
      observation(:local_rdf, second),
      observation(:ontop_cli, first)
    ]

    assert {:ok, receipt} = Differential.compare(:account_org, observations)
    assert receipt.verified?
    assert receipt.strategies == [:local_rdf, :ontop_cli, :protocol]
    assert map_size(receipt.result_sha256_by_strategy) == 3
    assert is_binary(receipt.receipt_sha256)

    assert :ok =
             Differential.require_strategies(receipt, [:local_rdf, :protocol, :ontop_cli])

    assert {:ok, reordered} =
             Differential.compare(:account_org, Enum.reverse(observations))

    assert reordered.receipt_sha256 == receipt.receipt_sha256
  end

  test "mismatched engine result remains a stable falsifying receipt" do
    assert {:ok, receipt} =
             Differential.compare(:account_org, [
               observation(:local_rdf, [%{"id" => "1"}]),
               observation(:protocol, [%{"id" => "2"}])
             ])

    refute receipt.verified?

    assert {:error, refusal} =
             Differential.require_strategies(receipt, [:local_rdf, :protocol])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert map_size(refusal.evidence.result_sha256_by_strategy) == 2
  end

  test "mixed lexical query identities are refused instead of guessed equivalent" do
    assert {:error, refusal} =
             Differential.compare(:account_org, [
               observation(:local_rdf, [%{"id" => "1"}], "query-a"),
               observation(:protocol, [%{"id" => "1"}], "query-b")
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert Enum.sort(refusal.evidence.query_sha256s) == ["query-a", "query-b"]
  end

  test "required topology closure reports missing execution strategies" do
    assert {:ok, receipt} =
             Differential.compare(:account_org, [
               observation(:protocol, [%{"id" => "1"}]),
               observation(:ontop_cli, [%{"id" => "1"}])
             ])

    assert {:error, refusal} =
             Differential.require_strategies(receipt, [:local_rdf, :protocol, :ontop_cli])

    assert refusal.evidence.missing == [:local_rdf]
  end
end
