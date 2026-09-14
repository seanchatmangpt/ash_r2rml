# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticSubject do
  @moduledoc """
  Exact identity for one admitted ontology-first semantic subject.

  `AshR2RML.SemanticIR` already carries the admitted ontology, application
  profile, and SHACL hashes. This module binds those three identities into one
  deterministic digest suitable for downstream manufacture. It does not hash
  generated Ash/R2RML/SQL projections and does not infer semantic equivalence
  between different source hashes.
  """

  alias AshR2RML.SemanticIR

  @domain "ash-r2rml-semantic-subject/v1"

  @enforce_keys [:ontology_hash, :profile_hash, :shacl_hash, :digest]
  defstruct [:ontology_hash, :profile_hash, :shacl_hash, :digest]

  @type t :: %__MODULE__{
          ontology_hash: String.t(),
          profile_hash: String.t(),
          shacl_hash: String.t(),
          digest: String.t()
        }

  @type refusal :: {:refused_semantic_subject, :ontology_hash | :profile_hash | :shacl_hash}

  @spec from_ir(SemanticIR.t()) :: {:ok, t()} | {:error, refusal()}
  def from_ir(%SemanticIR{} = ir) do
    with :ok <- present(:ontology_hash, ir.ontology_hash),
         :ok <- present(:profile_hash, ir.profile_hash),
         :ok <- present(:shacl_hash, ir.shacl_hash) do
      canonical =
        [
          @domain,
          field("ontology", ir.ontology_hash),
          field("profile", ir.profile_hash),
          field("shacl", ir.shacl_hash)
        ]
        |> Enum.join("\n")

      {:ok,
       %__MODULE__{
         ontology_hash: ir.ontology_hash,
         profile_hash: ir.profile_hash,
         shacl_hash: ir.shacl_hash,
         digest: sha256(canonical)
       }}
    end
  end

  @doc "Exact downstream manufacture input; generated projections remain outside the subject identity."
  @spec manufacture_input(t()) :: map()
  def manufacture_input(%__MODULE__{} = subject) do
    %{
      graph_digest: subject.digest,
      ontology_hash: subject.ontology_hash,
      profile_hash: subject.profile_hash,
      shacl_hash: subject.shacl_hash
    }
  end

  @doc "in-toto/SLSA-compatible resolved-material shape for the semantic subject."
  @spec resolved_material(t()) :: map()
  def resolved_material(%__MODULE__{} = subject) do
    %{
      "uri" => "urn:ash-r2rml:semantic-subject:" <> strip_sha256(subject.digest),
      "digest" => %{"sha256" => strip_sha256(subject.digest)}
    }
  end

  defp present(_field, value) when is_binary(value) and byte_size(value) > 0, do: :ok
  defp present(field, _value), do: {:error, {:refused_semantic_subject, field}}

  defp field(name, value), do: name <> ":" <> Integer.to_string(byte_size(value)) <> ":" <> value

  defp sha256(binary) do
    "sha256:" <>
      (:crypto.hash(:sha256, binary)
       |> Base.encode16(case: :lower))
  end

  defp strip_sha256("sha256:" <> hex), do: hex
end
