# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Integration do
  @moduledoc "Strict composition of the GGen runtime integration contract surfaces."

  alias AshR2RML.GgenRuntime.{
    Authority,
    Concurrency,
    DataContract,
    Eventing,
    Observability,
    Persistence,
    Resilience,
    Security,
    Subject,
    Transport
  }

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(input) when is_map(input) do
    with {:ok, subject} <- Subject.admit(Map.get(input, :subject, %{})),
         {:ok, authority} <- Authority.admit(Map.get(input, :authority, %{})),
         {:ok, observability} <- Observability.admit(Map.get(input, :observability, %{})),
         {:ok, resilience} <- Resilience.admit(Map.get(input, :resilience, %{})),
         {:ok, concurrency} <- Concurrency.admit(Map.get(input, :concurrency, %{})),
         {:ok, transport} <- Transport.admit(Map.get(input, :transport, %{})),
         {:ok, security} <- Security.admit(Map.get(input, :security, %{})),
         {:ok, data_contract} <- DataContract.admit(Map.get(input, :data_contract, %{})),
         {:ok, eventing} <- Eventing.admit(Map.get(input, :eventing, %{})),
         {:ok, persistence} <- Persistence.admit(Map.get(input, :persistence, %{})) do
      contract = %{
        subject: subject,
        authority: authority,
        observability: observability,
        resilience: resilience,
        concurrency: concurrency,
        transport: transport,
        security: security,
        data_contract: data_contract,
        eventing: eventing,
        persistence: persistence,
        marketplace_pack: "ash-runtime-integration-contract-pack",
        canonical_evidence: "ggen/ecosystem/ocel/current",
        standing: :construct_only
      }

      {:ok, Map.put(contract, :contract_digest, digest(contract))}
    end
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_INTEGRATION_INCOMPLETE}

  defp digest(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
