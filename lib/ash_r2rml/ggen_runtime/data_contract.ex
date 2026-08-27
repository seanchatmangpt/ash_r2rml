# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.DataContract do
  @moduledoc "Input/output schema and sanitization contract for generated runtime boundaries."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{input_schema: input, output_schema: output} = contract)
      when is_map(input) and map_size(input) > 0 and is_map(output) and map_size(output) > 0 do
    normalized =
      contract
      |> Map.put_new(:input_normalization, :explicit)
      |> Map.put_new(:output_sanitization, :explicit)

    {:ok, normalized}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_SCHEMA_CONTRACT_INCOMPLETE}
end
