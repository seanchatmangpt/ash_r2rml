# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.DeadlineTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Deadline

  test "admits bounded cooperative deadline" do
    assert {:ok, %{deadline_ms: 5_000, cancellation: :cooperative}} =
             Deadline.admit(%{deadline_ms: 5_000, cancellation: :cooperative})
  end

  test "refuses absent deadline" do
    assert {:error, :REFUSED_RUNTIME_DEADLINE_INCOMPLETE} = Deadline.admit(%{cancellation: :cooperative})
  end
end
