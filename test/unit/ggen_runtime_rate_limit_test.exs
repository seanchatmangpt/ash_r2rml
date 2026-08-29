# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.RateLimitTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.RateLimit

  test "admits bounded actor rate limit" do
    assert {:ok, %{overflow: :refuse}} =
             RateLimit.admit(%{limit: 100, window_ms: 60_000, partition_by: :actor})
  end

  test "refuses missing partition" do
    assert {:error, :REFUSED_RUNTIME_RATE_LIMIT_INCOMPLETE} =
             RateLimit.admit(%{limit: 100, window_ms: 60_000})
  end
end
