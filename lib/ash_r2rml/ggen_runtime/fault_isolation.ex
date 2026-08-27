# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.FaultIsolation do
  @moduledoc "Bounded circuit-breaker and bulkhead contracts for generated runtime seams."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{failure_threshold: threshold, max_concurrency: concurrency} = contract)
      when is_integer(threshold) and threshold >= 1 and threshold <= 100 and
             is_integer(concurrency) and concurrency >= 1 and concurrency <= 100_000 do
    {:ok, Map.put_new(contract, :open_behavior, :refuse)}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_FAULT_ISOLATION_UNBOUNDED}
end
