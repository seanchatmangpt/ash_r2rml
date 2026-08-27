# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.LifecycleTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Lifecycle

  test "admits deprecated capability with sunset" do
    assert {:ok, %{state: :deprecated, sunset: "2026-12-31"}} =
             Lifecycle.admit(%{state: :deprecated, sunset: "2026-12-31"})
  end

  test "refuses deprecation without sunset" do
    assert {:error, :REFUSED_RUNTIME_SUNSET_MISSING} = Lifecycle.admit(%{state: :deprecated})
  end
end
