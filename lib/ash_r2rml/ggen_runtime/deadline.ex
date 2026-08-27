# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Deadline do
  @moduledoc "Deadline/cancellation admission for bounded runtime work."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{deadline_ms: deadline, cancellation: cancellation} = contract)
      when is_integer(deadline) and deadline > 0 and cancellation in [:cooperative, :refuse_after_deadline] do
    {:ok, contract}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_DEADLINE_INCOMPLETE}
end
