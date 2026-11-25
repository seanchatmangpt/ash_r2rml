# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.GraphMaps do
  @moduledoc """
  Validation rules for graph maps attached to a resource, subject, property or reference.
  """

  import AshR2RML.Mapping.Validate.Shared, only: [absolute_iri?: 1, non_empty_string?: 1]

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.GraphMap
  alias AshR2RML.Mapping.Validate.Shared
  alias AshR2RML.Refusal

  @doc "Refusals for the resource-level graph maps."
  @spec resource(AshR2RML.Mapping.Resource.t()) :: [Refusal.t()]
  def resource(resource), do: check(resource.ash_resource, resource.graph_maps, resource)

  @doc """
  Refusals for a list of graph maps reported against `subject`.

  With a mapping `resource`, `:template` fields and `:column` values must be columns the
  mapping can supply; with `nil` only non-emptiness is checked.
  """
  @spec check(term(), [term()], AshR2RML.Mapping.Resource.t() | nil) :: [Refusal.t()]
  def check(subject, graph_maps, resource \\ nil) do
    available = if resource, do: Shared.available_columns(resource)
    Enum.flat_map(graph_maps, &graph_map(subject, &1, available))
  end

  defp graph_map(subject, %GraphMap{strategy: :constant, value: value}, _available) do
    if absolute_iri?(value) do
      []
    else
      [
        Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "constant graph IRI must be absolute", %{
          value: value
        })
      ]
    end
  end

  defp graph_map(subject, %GraphMap{strategy: strategy, value: value}, available)
       when strategy in [:template, :column] do
    if non_empty_string?(value) do
      case missing_columns(strategy, value, available) do
        [] ->
          []

        missing ->
          [
            Refusal.new(
              :REFUSED_INVALID_GRAPH_MAP,
              subject,
              "graph map references columns the mapping cannot supply",
              %{strategy: strategy, missing: missing}
            )
          ]
      end
    else
      [
        Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "graph map value must be non-empty", %{
          strategy: strategy
        })
      ]
    end
  end

  defp graph_map(subject, other, _available) do
    [
      Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "unsupported graph map", %{
        graph_map: inspect(other)
      })
    ]
  end

  defp missing_columns(_strategy, _value, nil), do: []

  defp missing_columns(:column, value, available) do
    if MapSet.member?(available, value), do: [], else: [value]
  end

  defp missing_columns(:template, value, available) do
    value
    |> Mapping.template_fields()
    |> Enum.reject(&MapSet.member?(available, &1))
  end
end
