# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Config do
  @moduledoc "Content-addressed dependency and runtime configuration admission."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{dependencies: dependencies, runtime: runtime}) when is_map(dependencies) and is_map(runtime) do
    if map_size(dependencies) == 0 or map_size(runtime) == 0 do
      {:error, :REFUSED_RUNTIME_CONFIG_INCOMPLETE}
    else
      {:ok,
       %{
         dependencies: dependencies,
         runtime: runtime,
         dependency_digest: digest(dependencies),
         runtime_config_digest: digest(runtime)
       }}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_CONFIG_INCOMPLETE}

  defp digest(term), do: term |> :erlang.term_to_binary([:deterministic]) |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
end
