# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Audit do
  @moduledoc "Audit contract binding actor, exact subject, action, and receipt."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{actor_id: actor, subject_digest: subject, action: action, receipt_id: receipt} = audit)
      when is_binary(actor) and byte_size(actor) > 0 and is_binary(subject) and byte_size(subject) == 64 and
             is_binary(action) and byte_size(action) > 0 and is_binary(receipt) and byte_size(receipt) > 0 do
    {:ok, Map.put_new(audit, :append_only, true)}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_AUDIT_INCOMPLETE}
end
