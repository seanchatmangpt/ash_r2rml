# SPDX-FileCopyrightText: 2026 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshNeo4j.SandboxTimeoutTest do
  @moduledoc false
  # Regression for #398: the holder transaction is held for the whole test, so
  # it must not inherit DBConnection's 15s default checkout timeout. This module
  # drives its own checkout (no shared `setup` checkout) so it can exercise the
  # `:timeout` option directly.
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias AshNeo4j.Neo4jHelper
  alias AshNeo4j.Sandbox

  setup_all do
    AshNeo4j.BoltyHelper.start()
  end

  test "checkout/1 passes :timeout to the holder transaction (short timeout disconnects)" do
    # With a short explicit timeout the held transaction is disconnected once it
    # outlives it — proving the :timeout reaches DBConnection.transaction at the
    # call site. If the timeout were dropped, the 15s default would apply and the
    # query below would still succeed, failing this assertion.
    log =
      capture_log(fn ->
        Sandbox.checkout(timeout: 300)
        Process.sleep(800)
        assert {:error, _} = Neo4jHelper.read_nodes(:SandboxTimeoutNode)
        Sandbox.rollback()
      end)

    assert log =~ "disconnected" or log =~ "timed out"
  end

  @tag :slow
  test "checkout/0 default keeps the holder transaction alive past 15s" do
    # The default is :infinity, so a transaction held longer than DBConnection's
    # 15s default still serves queries (the bug in #398 was a disconnect at 15s).
    Sandbox.checkout()
    Process.sleep(15_500)
    assert {:ok, %{records: []}} = Neo4jHelper.read_nodes(:SandboxTimeoutNode)
    Sandbox.rollback()
  end
end
