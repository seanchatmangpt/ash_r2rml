defmodule AshR2RML.VKG.Contract do
  @moduledoc """
  Exact-subject federation contract for one virtual knowledge graph source.

  The contract binds source descriptor identity, graph identity, mapping bytes,
  query bytes, and the subject template. It is deliberately CONSTRUCT/OBSERVE
  only: admission never grants mutation authority over the source.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.SourceIdentity

  @enforce_keys [
    :id,
    :source,
    :graph,
    :source_sha256,
    :mapping_sha256,
    :query_sha256,
    :subject_template,
    :mapping_path,
    :query_path
  ]

  defstruct [
    :id,
    :source,
    :graph,
    :source_sha256,
    :mapping_sha256,
    :query_sha256,
    :subject_template,
    :mapping_path,
    :query_path,
    :ontology_path,
    version: "1",
    capabilities: [:select],
    authority: :NONE,
    standing: :constructed_not_actuated
  ]

  @type t :: %__MODULE__{}

  @spec admit(t()) :: {:ok, t()} | {:error, Refusal.t()}
  def admit(%__MODULE__{} = contract) do
    with :ok <- validate_text(contract.id, :id),
         :ok <- validate_text(contract.source, :source),
         :ok <- validate_text(contract.graph, :graph),
         :ok <- validate_text(contract.subject_template, :subject_template),
         :ok <- validate_digest(contract.source_sha256, :source_sha256),
         :ok <- validate_digest(contract.mapping_sha256, :mapping_sha256),
         :ok <- validate_digest(contract.query_sha256, :query_sha256),
         :ok <- validate_path(contract.mapping_path, :mapping_path),
         :ok <- validate_path(contract.query_path, :query_path),
         :ok <- validate_authority(contract.authority),
         {:ok, identity} <-
           SourceIdentity.new(%{
             id: contract.id,
             uri: contract.source,
             graph: contract.graph,
             subject_template: contract.subject_template,
             version: contract.version
           }),
         :ok <- SourceIdentity.verify(identity, contract.source_sha256) do
      {:ok, contract}
    end
  end

  def admit(other) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_CONTRACT_SHAPE,
       :contract,
       "VKG contract must be an AshR2RML.VKG.Contract",
       %{value: inspect(other)}
     )}
  end

  @spec exact_subject?(t(), String.t()) :: boolean()
  def exact_subject?(%__MODULE__{id: id}, id), do: true
  def exact_subject?(_, _), do: false

  @spec identity(t()) :: map()
  def identity(%__MODULE__{} = contract) do
    %{
      id: contract.id,
      source: contract.source,
      graph: contract.graph,
      source_sha256: contract.source_sha256,
      mapping_sha256: contract.mapping_sha256,
      query_sha256: contract.query_sha256,
      version: contract.version
    }
  end

  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = contract) do
    contract
    |> identity()
    |> Map.put(:subject_template, contract.subject_template)
    |> canonical_hash()
  end

  defp validate_text(value, _field) when is_binary(value) and byte_size(value) > 0, do: :ok

  defp validate_text(value, field) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_CONTRACT_IDENTITY,
       field,
       "VKG contract field must be a non-empty string",
       %{field: field, value: inspect(value)}
     )}
  end

  defp validate_digest(value, _field)
       when is_binary(value) and byte_size(value) == 64 do
    if String.match?(value, ~r/\A[0-9a-f]{64}\z/) do
      :ok
    else
      digest_refusal(value)
    end
  end

  defp validate_digest(value, field) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_CONTRACT_IDENTITY,
       field,
       "VKG digest must be lowercase sha256 hex",
       %{field: field, value: inspect(value)}
     )}
  end

  defp digest_refusal(value) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_CONTRACT_IDENTITY,
       :digest,
       "VKG digest must be lowercase sha256 hex",
       %{value: value}
     )}
  end

  defp validate_path(path, _field) when is_binary(path) and byte_size(path) > 0, do: :ok

  defp validate_path(path, field) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_CONTRACT_IDENTITY,
       field,
       "VKG artifact path must be a non-empty string",
       %{field: field, value: inspect(path)}
     )}
  end

  defp validate_authority(:NONE), do: :ok

  defp validate_authority(authority) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_AUTHORITY_ESCALATION,
       :authority,
       "VKG contracts are observe-only and cannot carry actuation authority",
       %{authority: authority}
     )}
  end

  defp canonical_hash(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
