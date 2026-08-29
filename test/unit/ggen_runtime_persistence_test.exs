# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.PersistenceTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Persistence

  test "admits Ash-owned persistence" do
    assert {:ok, %{backend: :ash_postgres, transaction: :ash, direct_sql: false}} =
             Persistence.admit(%{backend: :ash_postgres, transaction: :ash})
  end

  test "refuses direct SQL authority escape" do
    assert {:error, :REFUSED_RUNTIME_PERSISTENCE_AUTHORITY_ESCAPE} =
             Persistence.admit(%{backend: :ash_postgres, transaction: :ash, direct_sql: true})
  end
end
