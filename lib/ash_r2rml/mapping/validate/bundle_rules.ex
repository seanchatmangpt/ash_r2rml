# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.BundleRules do
  @moduledoc """
  Cross-resource validation rules for a dependency-closed mapping bundle.
  """

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.Resource
  alias AshR2RML.Refusal

  @doc "Refusals for reference targets absent from the bundle or lacking a stable subject identity."
  @spec reference_targets(Resource.t(), %{optional(module()) => Resource.t()}) :: [Refusal.t()]
  def reference_targets(resource, by_resource) do
    Enum.flat_map(resource.reference_object_maps, &reference_target(resource, &1, by_resource))
  end

  @doc "Refusals for resources that share a subject contract and overlap in RDF classes."
  @spec duplicate_subject_contracts([Resource.t()]) :: [Refusal.t()]
  def duplicate_subject_contracts(resources) do
    resources
    |> Enum.group_by(fn resource -> {resource.logical_table, resource.subject_map} end)
    |> Enum.flat_map(fn
      {_key, [_one]} -> []
      {key, many} -> duplicate_contract_refusals(key, many)
    end)
  end

  defp reference_target(resource, reference, by_resource) do
    case Map.fetch(by_resource, reference.parent_resource) do
      {:ok, parent} -> parent_subject_identity(resource, reference, parent)
      :error -> [unmapped_target(resource, reference)]
    end
  end

  defp unmapped_target(resource, reference) do
    Refusal.new(
      :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
      {resource.ash_resource, reference.relationship},
      "reference object map target is absent from the dependency-closed mapping bundle",
      %{parent_resource: reference.parent_resource}
    )
  end

  defp parent_subject_identity(resource, reference, parent) do
    if Mapping.stable_subject_identity?(parent) do
      []
    else
      [
        Refusal.new(
          :REFUSED_R2RML_JOIN_WITHOUT_IDENTITY,
          {resource.ash_resource, reference.relationship},
          "parent triples map has no stable semantic subject identity",
          %{
            parent_resource: parent.ash_resource,
            subject_map: parent.subject_map,
            identities: parent.identities
          }
        )
      ]
    end
  end

  defp duplicate_contract_refusals(key, many) do
    if many |> Enum.map(&MapSet.new(&1.class_iris)) |> pairwise_overlap?() do
      [
        Refusal.new(
          :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
          Enum.map(many, & &1.ash_resource),
          "multiple mappings with overlapping RDF classes manufacture the same subject contract",
          %{subject_contract: key}
        )
      ]
    else
      []
    end
  end

  defp pairwise_overlap?([]), do: false

  defp pairwise_overlap?([head | tail]),
    do: Enum.any?(tail, &(not MapSet.disjoint?(head, &1))) or pairwise_overlap?(tail)
end
