# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Security do
  @moduledoc "Explicit actor, tenant, and policy context required by generated runtime seams."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{actor: actor, policy: policy} = context)
      when not is_nil(actor) and is_binary(policy) and byte_size(policy) > 0 do
    if Map.get(context, :tenant_required, false) and is_nil(Map.get(context, :tenant)) do
      {:error, :REFUSED_RUNTIME_TENANT_CONTEXT_MISSING}
    else
      {:ok, Map.put_new(context, :field_policy_mode, :ash_mediated)}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_POLICY_CONTEXT_MISSING}
end
