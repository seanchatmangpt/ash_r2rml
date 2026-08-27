# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Observability do
  @moduledoc "Content-addressed observability contract for runtime integrations."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{correlation_id: c, trace_id: t, evidence: e} = obs)
      when is_binary(c) and byte_size(c) > 0 and is_binary(t) and byte_size(t) > 0 and
             is_binary(e) and byte_size(e) > 0 do
    digest = :crypto.hash(:sha256, c <> "\0" <> t <> "\0" <> e) |> Base.encode16(case: :lower)
    {:ok, Map.put(obs, :observation_digest, digest)}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_OBSERVABILITY_INCOMPLETE}
end
