# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2RefusalCodesTest do
  @moduledoc """
  Refusal codes must say what actually went wrong. Option and authorization
  failures are not SPARQL feature gaps; I/O and syntax failures are not unproven
  equivalence claims.

  CONFLICTS with existing pins (they pin the old codes):
  obda_contract_fixes_test, refactor_w6_bounds_nil_test (bounds),
  obda_in_memory_security_opts_test, refactor_w9_guard_tests_test (guards),
  sparql_query_module_test, followup_rescue_sparql_test (admit/load_file).
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Action.Query, as: ActionQuery
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Query

  @select "SELECT ?s WHERE { ?s ?p ?o }"

  describe "invalid bounds" do
    for key <- [:max_rows, :max_triples, :timeout_ms] do
      test "#{key}: 0 is REFUSED_INVALID_OPTION" do
        assert {:error, error} = OBDA.query([], @select, [{unquote(key), 0}])
        assert error.code == :REFUSED_INVALID_OPTION
      end
    end
  end

  describe "read guards" do
    test "authorize?: false without allow_unauthorized is REFUSED_UNAUTHORIZED" do
      assert {:error, %Refusal{code: code}} =
               InMemory.check_read_guards(__MODULE__, [], authorize?: false)

      assert code == :REFUSED_UNAUTHORIZED
    end
  end

  describe "SPARQL admission" do
    test "missing file is not an equivalence refusal" do
      path = Path.join(System.tmp_dir!(), "red2_missing_#{System.unique_integer([:positive])}.rq")
      assert {:error, %Refusal{code: code}} = Query.load_file(path)
      assert code != :REFUSED_UNPROVEN_EQUIVALENCE
      assert code != :REFUSED_UNSUPPORTED_SPARQL_FEATURE
    end

    test "syntax error is not an equivalence refusal" do
      assert {:error, %Refusal{code: code}} = Query.admit("SELECT WHERE {{{ not sparql")
      assert code != :REFUSED_UNPROVEN_EQUIVALENCE
    end
  end

  describe "allow_sensitive option spelling" do
    test "Action.Query accepts allow_sensitive as OBDA and InMemory do" do
      assert {:ok, _} = ActionQuery.init(domain: __MODULE__, allow_sensitive: true)
    end

    test "Action.Query accepts allow_sensitive?" do
      assert {:ok, _} = ActionQuery.init(domain: __MODULE__, allow_sensitive?: true)
    end
  end
end
