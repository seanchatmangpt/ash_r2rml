# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.FaultIsolationTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.FaultIsolation

  test "admits bounded isolation" do
    assert {:ok, %{open_behavior: :refuse}} =
             FaultIsolation.admit(%{failure_threshold: 5, max_concurrency: 100})
  end

  test "refuses excessive concurrency" do
    assert {:error, :REFUSED_RUNTIME_FAULT_ISOLATION_UNBOUNDED} =
             FaultIsolation.admit(%{failure_threshold: 5, max_concurrency: 100_001})
  end
end
