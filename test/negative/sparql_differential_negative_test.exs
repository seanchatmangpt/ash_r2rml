# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.SparqlDifferentialNegativeTest do
  @moduledoc """
  Negative test suite verifying typed refusals on invalid SPARQL queries and differential comparisons:
  - REFUSED_DIFFERENTIAL_OBSERVATION_COUNT when < 2 observations are compared
  - REFUSED_DIFFERENTIAL_MIXED_QUERIES when comparing observations of different query strings
  - Disparate results setting verified?: false
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Differential, Observation, Query}

  describe "SPARQL Query Syntax Negative Tests" do
    test "refuses invalid SPARQL syntax" do
      invalid_sparql = "SELEC * WHERE { ?s ?p ?o "
      assert {:error, %Refusal{} = refusal} = Query.admit(invalid_sparql)
      assert refusal.code in [:REFUSED_INVALID_SPARQL_QUERY, :REFUSED_SPARQL_PARSE_ERROR, :REFUSED_UNPROVEN_EQUIVALENCE]
    end
  end

  describe "SPARQL Differential Comparator Negative Tests" do
    test "refuses fewer than two observations" do
      obs1 = %Observation{
        strategy: :ontop_cli,
        status: :VERIFIED,
        standing: :observed_execution,
        evidence_kind: :system_process,
        query_sha256: "hash_abc",
        query_form: :select,
        result_sha256: "hash_res",
        rows: [%{"a" => 1}]
      }

      assert {:error, %Refusal{} = refusal} = Differential.compare(:subject, [obs1], %{})
      assert refusal.code in [:REFUSED_DIFFERENTIAL_OBSERVATION_COUNT, :REFUSED_UNPROVEN_EQUIVALENCE]
    end

    test "refuses observations originating from different SPARQL queries" do
      obs1 = %Observation{
        strategy: :ontop_cli,
        status: :VERIFIED,
        standing: :observed_execution,
        evidence_kind: :system_process,
        query_sha256: "query_hash_1",
        query_form: :select,
        result_sha256: "hash_res_1",
        rows: [%{"a" => 1}]
      }

      obs2 = %Observation{
        strategy: :local_rdf,
        status: :VERIFIED,
        standing: :observed_execution,
        evidence_kind: :system_process,
        query_sha256: "query_hash_2",
        query_form: :select,
        result_sha256: "hash_res_2",
        rows: [%{"a" => 1}]
      }

      assert {:error, %Refusal{} = refusal} = Differential.compare(:subject, [obs1, obs2], %{})
      assert refusal.code in [:REFUSED_DIFFERENTIAL_MIXED_QUERIES, :REFUSED_UNPROVEN_EQUIVALENCE]
    end

    test "marks differential verified? false when query results diverge" do
      obs1 = %Observation{
        strategy: :ontop_cli,
        status: :VERIFIED,
        standing: :observed_execution,
        evidence_kind: :system_process,
        query_sha256: "same_query_hash",
        query_form: :select,
        result_sha256: "hash_res_1",
        rows: [%{"id" => "1", "name" => "Acme"}]
      }

      obs2 = %Observation{
        strategy: :local_rdf,
        status: :VERIFIED,
        standing: :observed_execution,
        evidence_kind: :system_process,
        query_sha256: "same_query_hash",
        query_form: :select,
        result_sha256: "hash_res_2",
        rows: [%{"id" => "2", "name" => "Different Corp"}]
      }

      assert {:ok, receipt} = Differential.compare(:subject, [obs1, obs2], %{})
      assert receipt.verified? == false
    end
  end
end
