# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.CacheContractTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.CacheContract

  test "admits explicit cache invalidation" do
    assert {:ok, %{invalidation: :on_write}} =
             CacheContract.admit(%{mode: :read_through, consistency: :strong, invalidation: :on_write})
  end

  test "refuses cache without invalidation" do
    assert {:error, :REFUSED_RUNTIME_CACHE_INVALIDATION_MISSING} =
             CacheContract.admit(%{mode: :read_through, consistency: :strong})
  end
end
