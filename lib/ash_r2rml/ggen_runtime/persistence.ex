# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Persistence do
  @moduledoc "Persistence contract that keeps Ash data-layer ownership explicit."

  @allowed [:ash_postgres, :ash_ets]

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{backend: backend, transaction: transaction} = contract)
      when backend in @allowed and transaction in [:none, :ash, :reactor] do
    if Map.get(contract, :direct_sql, false) do
      {:error, :REFUSED_RUNTIME_PERSISTENCE_AUTHORITY_ESCAPE}
    else
      {:ok, Map.put_new(contract, :direct_sql, false)}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_PERSISTENCE_UNSUPPORTED}
end
