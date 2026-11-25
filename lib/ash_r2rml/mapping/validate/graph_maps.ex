# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.GraphMaps do
  @moduledoc """
  Validation rules for graph maps attached to a resource, subject, property or reference.
  """

  import AshR2RML.Mapping.Validate.Shared, only: [absolute_iri?: 1, non_empty_string?: 1]

  alias AshR2RML.Mapping.GraphMap
  alias AshR2RML.Refusal

  @doc "Refusals for the resource-level graph maps."
  @spec resource(AshR2RML.Mapping.Resource.t()) :: [Refusal.t()]
  def resource(resource), do: check(resource.ash_resource, resource.graph_maps)

  @doc "Refusals for a list of graph maps reported against `subject`."
  @spec check(term(), [term()]) :: [Refusal.t()]
  def check(subject, graph_maps), do: Enum.flat_map(graph_maps, &graph_map(subject, &1))

  defp graph_map(subject, %GraphMap{strategy: :constant, value: value}) do
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

  defp graph_map(subject, %GraphMap{strategy: strategy, value: value})
       when strategy in [:template, :column] do
    if non_empty_string?(value) do
      []
    else
      [
        Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "graph map value must be non-empty", %{
          strategy: strategy
        })
      ]
    end
  end

  defp graph_map(subject, other) do
    [
      Refusal.new(:REFUSED_INVALID_GRAPH_MAP, subject, "unsupported graph map", %{
        graph_map: inspect(other)
      })
    ]
  end
end
