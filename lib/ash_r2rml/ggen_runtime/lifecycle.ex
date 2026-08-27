# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Lifecycle do
  @moduledoc "Feature-flag and deprecation admission for generated runtime interfaces."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{state: state} = contract) when state in [:active, :flagged, :deprecated] do
    cond do
      state == :flagged and is_nil(Map.get(contract, :flag)) -> {:error, :REFUSED_RUNTIME_FEATURE_FLAG_MISSING}
      state == :deprecated and is_nil(Map.get(contract, :sunset)) -> {:error, :REFUSED_RUNTIME_SUNSET_MISSING}
      true -> {:ok, contract}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_LIFECYCLE_INCOMPLETE}
end
