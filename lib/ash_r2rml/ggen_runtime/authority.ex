# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Authority do
  @moduledoc "Fail-closed authority admission for generated runtime seams."

  @allowed_actions [:select, :construct, :verify]

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{policy: policy, action: action} = authority)
      when is_binary(policy) and byte_size(policy) > 0 and action in @allowed_actions do
    if Map.get(authority, :direct_actuation, false) do
      {:error, :REFUSED_RUNTIME_AMBIENT_DO_AUTHORITY}
    else
      {:ok, Map.put(authority, :direct_actuation, false)}
    end
  end

  def admit(%{action: :do}), do: {:error, :REFUSED_RUNTIME_AMBIENT_DO_AUTHORITY}
  def admit(_), do: {:error, :REFUSED_RUNTIME_AUTHORITY_MISSING}
end
