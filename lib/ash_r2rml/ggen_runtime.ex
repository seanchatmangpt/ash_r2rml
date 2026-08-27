# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime do
  @moduledoc """
  Manufactures deterministic runtime-integration input for GGen without actuation.

  This module is a SELECT/CONSTRUCT boundary. It binds an exact repository subject,
  explicit authority policy, runtime configuration, and replay identity into a
  content-addressed map that `ash-runtime-integration-contract-pack` can consume.
  """

  @type exact_subject :: %{required(:repo) => String.t(), required(:base) => String.t(), required(:head) => String.t()}

  @spec contract(map()) :: {:ok, map()} | {:error, atom()}
  def contract(%{subject: subject, authority: authority, runtime: runtime} = input)
      when is_map(subject) and is_map(authority) and is_map(runtime) do
    with :ok <- validate_subject(subject),
         :ok <- validate_authority(authority),
         {:ok, digest} <- digest(runtime) do
      replay_key = Map.get(input, :replay_key) || digest({subject, runtime}) |> elem(1)

      {:ok,
       %{
         standing: :construct_only,
         status: :PARTIAL_ALIVE,
         subject: subject,
         authority: authority,
         runtime: runtime,
         runtime_digest: digest,
         replay_key: replay_key,
         marketplace_pack: "ash-runtime-integration-contract-pack",
         canonical_evidence: "ggen/ecosystem/ocel/current"
       }}
    end
  end

  def contract(_), do: {:error, :REFUSED_RUNTIME_CONTRACT_INCOMPLETE}

  defp validate_subject(%{repo: repo, base: base, head: head})
       when is_binary(repo) and byte_size(repo) > 2 and is_binary(base) and byte_size(base) > 0 and
              is_binary(head) and byte_size(head) >= 7,
       do: :ok

  defp validate_subject(_), do: {:error, :REFUSED_RUNTIME_SUBJECT_NOT_EXACT}

  defp validate_authority(%{policy: policy, action: action})
       when not is_nil(policy) and not is_nil(action),
       do: :ok

  defp validate_authority(_), do: {:error, :REFUSED_RUNTIME_AUTHORITY_MISSING}

  defp digest(term) do
    value = term |> :erlang.term_to_binary() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
    {:ok, value}
  end
end
