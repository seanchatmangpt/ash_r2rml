# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.DomainError do
  @moduledoc "Typed domain-error projection preserving refusal and retry semantics."

  @spec normalize(map()) :: {:ok, map()} | {:error, atom()}
  def normalize(%{code: code, class: :refusal} = error) when is_binary(code) and byte_size(code) > 0 do
    {:ok, error |> Map.put(:retryable, false) |> Map.put_new(:standing, :refused)}
  end

  def normalize(%{code: code, class: :transient} = error) when is_binary(code) and byte_size(code) > 0 do
    {:ok, Map.put_new(error, :retryable, true)}
  end

  def normalize(_), do: {:error, :REFUSED_RUNTIME_DOMAIN_ERROR_UNTYPED}
end
