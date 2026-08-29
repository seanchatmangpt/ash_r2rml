# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Idempotency do
  @moduledoc "Idempotency admission bound to an exact receipt namespace."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{key: key, receipt_namespace: namespace} = contract)
      when is_binary(key) and byte_size(key) > 0 and is_binary(namespace) and byte_size(namespace) > 0 do
    {:ok, Map.put_new(contract, :replay_behavior, :return_prior_receipt)}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_IDEMPOTENCY_INCOMPLETE}
end
