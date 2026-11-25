# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.References do
  @moduledoc """
  Validation rules for reference object maps (relationships), joins and many-to-many bridges.
  """

  import AshR2RML.Mapping.Validate.Shared

  alias AshR2RML.Mapping.Validate.GraphMaps
  alias AshR2RML.Mapping.{JoinCondition, LogicalTable, ReferenceObjectMap, Resource}
  alias AshR2RML.Refusal

  @bridge_keys [
    :source_parent_column,
    :source_join_column,
    :destination_join_column,
    :destination_parent_column
  ]

  @doc "Refusals for every reference object map of the resource."
  @spec check(Resource.t()) :: [Refusal.t()]
  def check(resource), do: Enum.flat_map(resource.reference_object_maps, &reference(resource, &1))

  @doc "Refusals for repeated `(relationship, predicate)` reference object maps."
  @spec duplicates(Resource.t()) :: [Refusal.t()]
  def duplicates(resource) do
    resource.reference_object_maps
    |> duplicate_keys(&{&1.relationship, &1.predicate_iri})
    |> Enum.map(fn {relationship, predicate} = key ->
      Refusal.new(
        :REFUSED_AMBIGUOUS_RELATIONSHIP,
        {resource.ash_resource, relationship},
        "duplicate (relationship, predicate) reference object map",
        %{key: key, predicate_iri: predicate}
      )
    end)
  end

  defp reference(resource, reference) do
    subject = {resource.ash_resource, reference.relationship}

    base =
      []
      |> maybe_add(predicate(subject, reference))
      |> maybe_add(inverse(subject, reference))

    base ++
      joins(resource, reference) ++
      GraphMaps.check(subject, reference.graph_maps)
  end

  defp predicate(subject, reference) do
    if not absolute_iri?(reference.predicate_iri) do
      Refusal.new(
        :REFUSED_RELATIONSHIP_WITHOUT_PREDICATE,
        subject,
        "relationship predicate IRI must be absolute",
        %{predicate_iri: reference.predicate_iri}
      )
    end
  end

  defp inverse(subject, reference) do
    if reference.inverse_predicate && not absolute_iri?(reference.inverse_predicate) do
      Refusal.new(
        :REFUSED_UNPROVEN_EQUIVALENCE,
        subject,
        "inverse predicate must be an absolute IRI when supplied",
        %{inverse_predicate: reference.inverse_predicate}
      )
    end
  end

  defp joins(resource, %ReferenceObjectMap{metadata: %{kind: :many_to_many}} = reference),
    do: many_to_many_bridge(resource, reference)

  defp joins(resource, reference) do
    subject = {resource.ash_resource, reference.relationship}

    []
    |> maybe_add(requires_join(subject, reference))
    |> Kernel.++(Enum.flat_map(reference.joins, &join(resource, subject, reference, &1)))
  end

  # Column existence is checked only when the mapping declares its columns
  # (`metadata.attribute_columns`); the parent side is checked only for
  # self-referential relationships, since this rule group sees one resource.
  defp dangling_column(resource, subject, reference, %JoinCondition{child: child, parent: parent}) do
    if declared_columns?(resource) do
      available = available_columns(resource)

      [{:child, child, true}, {:parent, parent, reference.parent_resource == resource.ash_resource}]
      |> Enum.filter(fn {_side, column, checked?} -> checked? and not MapSet.member?(available, column) end)
      |> Enum.map(fn {side, column, _checked?} ->
        Refusal.new(
          :REFUSED_INVALID_JOIN_CONDITION,
          subject,
          "join #{side} column is not a column of the mapped resource",
          %{side: side, column: column, available: available |> MapSet.to_list() |> Enum.sort()}
        )
      end)
    else
      []
    end
  end

  defp declared_columns?(resource) do
    match?(%{attribute_columns: columns} when is_map(columns) and map_size(columns) > 0, resource.metadata)
  end

  defp requires_join(subject, reference) do
    if reference.joins == [] do
      Refusal.new(
        :REFUSED_INVALID_JOIN_CONDITION,
        subject,
        "reference object map requires at least one join condition"
      )
    end
  end

  defp many_to_many_bridge(resource, reference) do
    metadata = reference.metadata
    subject = {resource.ash_resource, reference.relationship}

    []
    |> maybe_add(bridge_through_table(subject, Map.get(metadata, :through_logical_table)))
    |> maybe_add(bridge_complete(subject, metadata, bridge_columns(metadata)))
  end

  defp bridge_columns(metadata) do
    cond do
      Enum.all?(@bridge_keys, &Map.has_key?(metadata, &1)) ->
        Enum.map(@bridge_keys, &Map.fetch!(metadata, &1))

      match?(%JoinCondition{}, Map.get(metadata, :source_to_join)) and
          match?(%JoinCondition{}, Map.get(metadata, :join_to_destination)) ->
        a = metadata.source_to_join
        b = metadata.join_to_destination
        [a.child, a.parent, b.child, b.parent]

      true ->
        []
    end
  end

  defp bridge_through_table(subject, through) do
    if not match?(%LogicalTable{}, through) do
      Refusal.new(
        :REFUSED_INVALID_LOGICAL_TABLE,
        subject,
        "many_to_many reference requires a normalized through logical table"
      )
    end
  end

  defp bridge_complete(subject, metadata, columns) do
    if columns == [] or Enum.any?(columns, &(not non_empty_string?(&1))) do
      Refusal.new(
        :REFUSED_INVALID_JOIN_CONDITION,
        subject,
        "many_to_many reference requires complete source/bridge/destination join columns",
        %{metadata: metadata}
      )
    end
  end

  defp join(resource, subject, reference, %JoinCondition{child: child, parent: parent} = join) do
    if non_empty_string?(child) and non_empty_string?(parent) do
      dangling_column(resource, subject, reference, join)
    else
      [
        Refusal.new(
          :REFUSED_INVALID_JOIN_CONDITION,
          subject,
          "join child and parent columns must both be non-empty",
          %{child: child, parent: parent}
        )
      ]
    end
  end

  defp join(_resource, subject, _reference, other) do
    [
      Refusal.new(:REFUSED_INVALID_JOIN_CONDITION, subject, "join must be a JoinCondition", %{
        join: inspect(other)
      })
    ]
  end
end
