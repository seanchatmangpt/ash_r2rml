# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.CacheContract do
  @moduledoc "Cache admission that makes consistency and invalidation explicit."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{mode: mode, consistency: consistency} = contract)
      when mode in [:none, :read_through, :write_through] and consistency in [:strong, :eventual] do
    cond do
      mode == :none -> {:ok, Map.put(contract, :invalidation, :not_applicable)}
      is_nil(Map.get(contract, :invalidation)) -> {:error, :REFUSED_RUNTIME_CACHE_INVALIDATION_MISSING}
      true -> {:ok, contract}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_CACHE_CONTRACT_INCOMPLETE}
end
