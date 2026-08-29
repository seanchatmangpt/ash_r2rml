# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.RateLimit do
  @moduledoc "Bounded rate-limit contract with an explicit partition key."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{limit: limit, window_ms: window, partition_by: partition} = contract)
      when is_integer(limit) and limit > 0 and is_integer(window) and window > 0 and
             partition in [:actor, :tenant, :subject] do
    {:ok, Map.put_new(contract, :overflow, :refuse)}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_RATE_LIMIT_INCOMPLETE}
end
