# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Isolation do
  @moduledoc "Explicit tenant and transaction isolation contract."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{tenant: tenant, transaction: transaction} = contract)
      when tenant in [:none, :attribute, :context] and transaction in [:read_committed, :repeatable_read, :serializable] do
    {:ok, contract}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_ISOLATION_INCOMPLETE}
end
