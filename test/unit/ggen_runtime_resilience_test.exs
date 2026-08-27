# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ResilienceTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Resilience

  test "admits bounded retry policy" do
    assert {:ok, %{timeout_ms: 5000, max_attempts: 3, cancellable: true}} =
             Resilience.admit(%{timeout_ms: 5000, max_attempts: 3})
  end

  test "refuses unbounded retry counts" do
    assert {:error, :REFUSED_RUNTIME_RETRY_UNBOUNDED} =
             Resilience.admit(%{timeout_ms: 5000, max_attempts: 11})
  end
end
