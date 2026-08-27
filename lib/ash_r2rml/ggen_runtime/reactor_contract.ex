# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ReactorContract do
  @moduledoc "Ash.Reactor step and compensation admission without inventing actuation authority."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{step: step, on_error: :refuse} = contract) when is_binary(step) and byte_size(step) > 0 do
    if Map.get(contract, :consequential, false) and is_nil(Map.get(contract, :compensation)) do
      {:error, :REFUSED_RUNTIME_COMPENSATION_MISSING}
    else
      {:ok, Map.put_new(contract, :rollback_order, :reverse)}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_REACTOR_CONTRACT_INCOMPLETE}
end
