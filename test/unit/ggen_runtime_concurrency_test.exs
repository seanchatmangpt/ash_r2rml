# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Concurrency

  test "admits optimistic lock with explicit version field" do
    assert {:ok, %{strategy: :optimistic, version_field: :version, conflict: :refuse}} =
             Concurrency.admit(%{strategy: :optimistic, version_field: :version, conflict: :refuse})
  end

  test "refuses missing version precondition" do
    assert {:error, :REFUSED_RUNTIME_VERSION_PRECONDITION_MISSING} =
             Concurrency.admit(%{strategy: :optimistic})
  end
end
