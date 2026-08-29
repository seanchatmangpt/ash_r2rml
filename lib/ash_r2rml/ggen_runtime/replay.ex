# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Replay do
  @moduledoc "Replay admission requiring exact contract and receipt identities."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{contract_digest: contract, receipt_id: receipt} = replay)
      when is_binary(contract) and byte_size(contract) == 64 and is_binary(receipt) and byte_size(receipt) > 0 do
    {:ok, Map.put_new(replay, :mode, :deterministic)}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_REPLAY_IDENTITY_INCOMPLETE}
end
