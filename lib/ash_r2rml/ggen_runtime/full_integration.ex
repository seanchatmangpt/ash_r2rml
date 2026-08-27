# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.FullIntegration do
  @moduledoc "Full consumer admission for the Marketplace Ash runtime integration contract pack."

  alias AshR2RML.GgenRuntime.{
    Audit,
    CacheContract,
    Config,
    Deadline,
    FaultIsolation,
    Idempotency,
    Integration,
    Isolation,
    Lifecycle,
    RateLimit,
    ReactorContract,
    Replay
  }

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(input) when is_map(input) do
    with {:ok, core} <- Integration.admit(input),
         {:ok, idempotency} <- Idempotency.admit(Map.get(input, :idempotency, %{})),
         {:ok, reactor} <- ReactorContract.admit(Map.get(input, :reactor, %{})),
         {:ok, fault_isolation} <- FaultIsolation.admit(Map.get(input, :fault_isolation, %{})),
         {:ok, cache} <- CacheContract.admit(Map.get(input, :cache, %{})),
         {:ok, lifecycle} <- Lifecycle.admit(Map.get(input, :lifecycle, %{})),
         {:ok, rate_limit} <- RateLimit.admit(Map.get(input, :rate_limit, %{})),
         {:ok, audit} <- Audit.admit(Map.get(input, :audit, %{})),
         {:ok, replay} <- Replay.admit(Map.get(input, :replay, %{})),
         {:ok, config} <- Config.admit(Map.get(input, :config, %{})),
         {:ok, deadline} <- Deadline.admit(Map.get(input, :deadline, %{})),
         {:ok, isolation} <- Isolation.admit(Map.get(input, :isolation, %{})) do
      {:ok,
       core
       |> Map.put(:idempotency, idempotency)
       |> Map.put(:reactor, reactor)
       |> Map.put(:fault_isolation, fault_isolation)
       |> Map.put(:cache, cache)
       |> Map.put(:lifecycle, lifecycle)
       |> Map.put(:rate_limit, rate_limit)
       |> Map.put(:audit, audit)
       |> Map.put(:replay, replay)
       |> Map.put(:config, config)
       |> Map.put(:deadline, deadline)
       |> Map.put(:isolation, isolation)
       |> Map.put(:contract_level, :full)}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_FULL_INTEGRATION_INCOMPLETE}
end
