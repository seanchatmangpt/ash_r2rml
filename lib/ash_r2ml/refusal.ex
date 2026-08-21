# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Refusal do
  @moduledoc "Typed fail-closed refusal emitted by ontology-first admission."

  @enforce_keys [:code, :subject, :detail]
  defstruct [:code, :subject, :detail, evidence: %{}]

  @type code ::
          :REFUSED_UNMAPPED_RESOURCE_CLASS
          | :REFUSED_ATTRIBUTE_WITHOUT_PREDICATE
          | :REFUSED_INVALID_SUBJECT_TEMPLATE
          | :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY
          | :REFUSED_RELATIONSHIP_WITHOUT_TARGET_MAP
          | :REFUSED_CARDINALITY_STORAGE_MISMATCH
          | :REFUSED_DATATYPE_CAST_NOT_LOSSLESS
          | :REFUSED_UNPROVEN_EQUIVALENCE
          | :REFUSED_R2RML_JOIN_KEY_NOT_UNIQUE
          | :REFUSED_OPEN_WORLD_RELATIONAL_PROJECTION
          | :REFUSED_UNKNOWN_ATTRIBUTE
          | :REFUSED_INVALID_IRI
          | :REFUSED_RDF_PARSE
          | :REFUSED_SHACL_PROFILE_INCOMPLETE
          | :REFUSED_UNSUPPORTED_SHACL_PATH
          | :REFUSED_PROJECTION_NOT_IMPLEMENTED
          | :REFUSED_OBDA_EXECUTION

  @type t :: %__MODULE__{
          code: code(),
          subject: term(),
          detail: String.t(),
          evidence: map()
        }

  def new(code, subject, detail, evidence \\ %{}) do
    %__MODULE__{code: code, subject: subject, detail: detail, evidence: evidence}
  end
end

defmodule AshR2ml.DfCM do
  @moduledoc """
  Preserves the maximal lawful relational candidate set until an admitted
  profile selects a representation that the compiler can actually manufacture.

  Candidate membership is deliberately broader than executable support. Array,
  JSONB, and computed projections remain visible alternatives instead of being
  collapsed prematurely into foreign keys or join tables.
  """

  alias AshR2ml.SemanticIR.Relationship

  @candidate_only [:array, :jsonb, :computed_projection]

  @spec storage_candidates(Relationship.t()) :: [Relationship.storage_strategy()]
  def storage_candidates(%Relationship{max_count: 1, properties: []}),
    do: [:foreign_key, :association_resource, :jsonb, :computed_projection]

  def storage_candidates(%Relationship{max_count: 1}),
    do: [:association_resource, :jsonb, :computed_projection]

  def storage_candidates(%Relationship{max_count: nil, properties: []}),
    do: [:join_table, :association_resource, :array, :jsonb, :computed_projection]

  def storage_candidates(%Relationship{max_count: max, properties: []})
      when is_integer(max) and max > 1,
      do: [:join_table, :association_resource, :array, :jsonb, :computed_projection]

  def storage_candidates(%Relationship{}),
    do: [:association_resource, :jsonb, :computed_projection]

  def select(%Relationship{storage_strategy: {:unsupported, raw}} = relationship) do
    case normalize_strategy(raw) do
      nil ->
        {:error,
         AshR2ml.Refusal.new(
           :REFUSED_CARDINALITY_STORAGE_MISMATCH,
           relationship.name,
           "unknown relational storage strategy",
           %{strategy: raw, candidates: storage_candidates(relationship)}
         )}

      strategy ->
        select(%{relationship | storage_strategy: strategy})
    end
  end

  def select(%Relationship{storage_strategy: strategy} = relationship) when not is_nil(strategy) do
    candidates = storage_candidates(relationship)

    cond do
      strategy not in candidates ->
        {:error,
         AshR2ml.Refusal.new(
           :REFUSED_CARDINALITY_STORAGE_MISMATCH,
           relationship.name,
           "selected storage strategy #{inspect(strategy)} is not lawful for admitted cardinality/properties",
           %{candidates: candidates}
         )}

      strategy in @candidate_only ->
        {:error,
         AshR2ml.Refusal.new(
           :REFUSED_PROJECTION_NOT_IMPLEMENTED,
           relationship.name,
           "storage strategy is admitted as a DfCM candidate but its executable projection is not implemented yet",
           %{strategy: strategy, candidates: candidates}
         )}

      true ->
        {:ok, %{relationship | storage_candidates: candidates}}
    end
  end

  def select(%Relationship{} = relationship) do
    candidates = storage_candidates(relationship)

    case candidates do
      [only] -> {:ok, %{relationship | storage_candidates: candidates, storage_strategy: only}}
      _ -> {:ok, %{relationship | storage_candidates: candidates}}
    end
  end

  defp normalize_strategy(:array), do: :array
  defp normalize_strategy(:jsonb), do: :jsonb
  defp normalize_strategy(:computed_projection), do: :computed_projection
  defp normalize_strategy("array"), do: :array
  defp normalize_strategy("jsonb"), do: :jsonb
  defp normalize_strategy("computed_projection"), do: :computed_projection
  defp normalize_strategy(_), do: nil
end
