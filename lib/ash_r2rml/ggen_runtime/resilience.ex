# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Resilience do
  @moduledoc "Bounded retry/timeout/cancellation policy for generated runtime integrations."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{timeout_ms: timeout, max_attempts: attempts} = policy)
      when is_integer(timeout) and timeout > 0 and is_integer(attempts) and attempts >= 1 and attempts <= 10 do
    {:ok, Map.put_new(policy, :cancellable, true)}
  end

  def admit(%{max_attempts: attempts}) when is_integer(attempts) and attempts > 10,
    do: {:error, :REFUSED_RUNTIME_RETRY_UNBOUNDED}

  def admit(_), do: {:error, :REFUSED_RUNTIME_RESILIENCE_INCOMPLETE}
end
