# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Concurrency do
  @moduledoc "Version-precondition and optimistic-lock contract admission."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{strategy: :optimistic, version_field: field, conflict: :refuse} = policy)
      when is_atom(field) or is_binary(field) do
    {:ok, policy}
  end

  def admit(%{strategy: :optimistic}), do: {:error, :REFUSED_RUNTIME_VERSION_PRECONDITION_MISSING}
  def admit(%{strategy: :pessimistic}), do: {:error, :REFUSED_RUNTIME_LOCK_AUTHORITY_UNDECLARED}
  def admit(_), do: {:error, :REFUSED_RUNTIME_CONCURRENCY_UNSUPPORTED}
end
