# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.IsolationTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Isolation

  test "admits explicit tenant and transaction isolation" do
    assert {:ok, %{tenant: :context, transaction: :serializable}} =
             Isolation.admit(%{tenant: :context, transaction: :serializable})
  end

  test "refuses unspecified isolation" do
    assert {:error, :REFUSED_RUNTIME_ISOLATION_INCOMPLETE} = Isolation.admit(%{tenant: :context})
  end
end
