# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Security.Fields do
  @moduledoc """
  Pure extraction of the source columns read by mapping term maps.

  Used by `AshR2RML.Security` to find every column a subject, graph or object term map
  depends on. Unknown strategies yield `[]`; callers decide what an empty list means.

  ## Examples

      iex> AshR2RML.Security.Fields.template_columns("http://schema.org/{id}/{kind}")
      ["id", "kind"]

      iex> AshR2RML.Security.Fields.term_map_fields(%{strategy: :column, value: "name"})
      ["name"]

      iex> AshR2RML.Security.Fields.term_map_fields(%{strategy: :constant, value: "x"})
      []

      iex> AshR2RML.Security.Fields.subject_fields(%{strategy: :blank_node, value: "b{id}"})
      ["id"]
  """

  @doc "Placeholder names (`{name}`) in a template string, in order."
  @spec template_columns(String.t()) :: [String.t()]
  def template_columns(template) when is_binary(template) do
    ~r/\{([^{}]+)\}/ |> Regex.scan(template, capture: :all_but_first) |> List.flatten()
  end

  @doc "Columns read by a graph or object term map: the column itself or template placeholders."
  @spec term_map_fields(map()) :: [term()]
  def term_map_fields(%{strategy: :column, value: value}), do: [value]

  def term_map_fields(%{strategy: :template, value: value}) when is_binary(value),
    do: template_columns(value)

  def term_map_fields(_), do: []

  @doc "Columns read by a subject map (column, template or blank-node template)."
  @spec subject_fields(map()) :: [term()]
  def subject_fields(%{strategy: :column, value: value}), do: [value]

  def subject_fields(%{strategy: strategy, value: value})
      when strategy in [:template, :blank_node] and is_binary(value),
      do: template_columns(value)

  def subject_fields(_), do: []

  @doc "Every graph map reachable from a mapping, at all levels."
  @spec all_graph_maps(map()) :: [map()]
  def all_graph_maps(mapping) do
    mapping.graph_maps ++
      mapping.subject_map.graph_maps ++
      Enum.flat_map(mapping.predicate_object_maps, &(&1.graph_maps ++ &1.object_map.graph_maps)) ++
      Enum.flat_map(mapping.reference_object_maps, & &1.graph_maps)
  end
end
