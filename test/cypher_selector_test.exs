# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.CypherSelectorTest do
  @moduledoc """
  The `%Query{}` run path must emit the `CYPHER 25` language selector exactly
  once (#397). `render/2` defaults to `prefix?: true`, so the `%Query{}` clauses
  of `run/1` and `run_expecting_deletions/1` render unprefixed and let the
  arity-2 string clause add the single selector — otherwise it is doubled
  (`CYPHER 25 CYPHER 25 …`).
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshNeo4j.Cypher
  alias AshNeo4j.Cypher.{DetachDelete, Match, Query, Return}
  alias AshNeo4j.Sandbox

  setup_all do
    AshNeo4j.BoltyHelper.start()
    :ok
  end

  describe "CYPHER 25 selector on the %Query{} run path" do
    @describetag :cypher25

    setup do
      # The selector is only emitted on a Cypher 25 server (the Bolt6 / 2026.05
      # pool). run/2 and run_expecting_deletions/2 log the rendered Cypher at
      # :debug, so capture it there.
      Process.put(:ash_neo4j_pool, Bolt6)
      Sandbox.checkout()

      level = Logger.level()
      Logger.configure(level: :debug)

      on_exit(fn ->
        Logger.configure(level: level)
        Sandbox.rollback()
      end)

      :ok
    end

    test "run/1 emits a single selector" do
      query = %Query{
        clauses: [%Match{pattern: "(n:Selector397 {id: $id})"}, %Return{items: ["n"]}],
        params: %{id: "x"}
      }

      log = capture_log(fn -> Cypher.run(query) end)

      assert log =~ "AshNeo4j.Cypher: run(CYPHER 25 MATCH"
      refute log =~ "CYPHER 25 CYPHER 25"
    end

    test "run_expecting_deletions/1 emits a single selector" do
      query = %Query{
        clauses: [%Match{pattern: "(n:Selector397)"}, %DetachDelete{items: ["n"]}],
        params: %{}
      }

      log = capture_log(fn -> Cypher.run_expecting_deletions(query) end)

      assert log =~ "AshNeo4j.Cypher: run_expecting_deletions(CYPHER 25 MATCH"
      refute log =~ "CYPHER 25 CYPHER 25"
    end
  end
end
