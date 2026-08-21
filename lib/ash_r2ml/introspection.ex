# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.Introspection do
  @moduledoc """
  Data-layer-aware Ash introspection used before semantic mapping serialization.

  AshR2ML never owns persistence. This module asks Ash and, when present, the
  active relational data layer for the table/schema/column/join facts needed by
  the normalized mapping IR. Optional adapters are invoked dynamically so
  AshR2ML does not make AshPostgres a runtime requirement for non-relational
  consumers.
  """

  alias AshR2ML.Mapping.{JoinCondition, LogicalTable}
  alias AshR2ML.Refusal

  @spec logical_table(module(), keyword()) ::
          {:ok, LogicalTable.t()} | {:error, Refusal.t()}
  def logical_table(resource, opts \\ []) do
    explicit_table = Keyword.get(opts, :table_name)
    explicit_query = Keyword.get(opts, :sql_query)
    explicit_schema = Keyword.get(opts, :schema)

    case {explicit_table, explicit_query} do
      {table, nil} when is_binary(table) and table != "" ->
        {:ok, %LogicalTable{table_name: table, schema: explicit_schema}}

      {nil, query} when is_binary(query) and query != "" ->
        {:ok, %LogicalTable{sql_query: query, schema: explicit_schema}}

      {nil, nil} ->
        infer_logical_table(resource)

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_LOGICAL_TABLE,
           resource,
           "exactly one of table_name or sql_query may be configured"
         )}
    end
  end

  @spec column(module(), atom()) :: {:ok, String.t()} | {:error, Refusal.t()}
  def column(resource, attribute_name) do
    case Ash.Resource.Info.attribute(resource, attribute_name) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           {resource, attribute_name},
           "Ash attribute does not exist"
         )}

      attribute ->
        {:ok, to_string(attribute.source || attribute.name)}
    end
  end

  @spec identities(module()) :: [[atom()]]
  def identities(resource) do
    primary = List.wrap(Ash.Resource.Info.primary_key(resource))

    declared =
      if function_exported?(Ash.Resource.Info, :identities, 1) do
        Ash.Resource.Info.identities(resource)
        |> Enum.map(&List.wrap(&1.keys))
      else
        []
      end

    [primary | declared]
    |> Enum.reject(&(&1 == []))
    |> Enum.map(&Enum.sort/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec stable_subject_identity?(module(), [String.t()]) :: boolean()
  def stable_subject_identity?(resource, template_fields) do
    columns_by_attribute =
      Ash.Resource.Info.attributes(resource)
      |> Map.new(fn attribute -> {to_string(attribute.source || attribute.name), attribute.name} end)

    template_keys =
      template_fields
      |> Enum.map(&Map.get(columns_by_attribute, &1))

    Enum.all?(template_keys, &is_atom/1) and
      Enum.any?(identities(resource), fn identity ->
        MapSet.subset?(MapSet.new(template_keys), MapSet.new(identity)) or
          MapSet.subset?(MapSet.new(identity), MapSet.new(template_keys))
      end)
  end

  @spec relationship(module(), atom()) :: {:ok, map()} | {:error, Refusal.t()}
  def relationship(resource, relationship_name) do
    case Ash.Resource.Info.relationship(resource, relationship_name) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_AMBIGUOUS_RELATIONSHIP,
           {resource, relationship_name},
           "Ash relationship does not exist"
         )}

      relationship ->
        relationship_metadata(resource, relationship)
    end
  end

  defp relationship_metadata(resource, relationship) do
    type = Map.get(relationship, :type)

    case type do
      :many_to_many -> many_to_many_metadata(resource, relationship)
      type when type in [:belongs_to, :has_one, :has_many] -> simple_relationship_metadata(resource, relationship)
      _ ->
        {:error,
         Refusal.new(
           :REFUSED_AMBIGUOUS_RELATIONSHIP,
           {resource, relationship.name},
           "relationship kind has no admitted relational R2RML projection",
           %{type: type}
         )}
    end
  end

  defp simple_relationship_metadata(resource, relationship) do
    with {:ok, child} <- column(resource, relationship.source_attribute),
         {:ok, parent} <- column(relationship.destination, relationship.destination_attribute) do
      {:ok,
       %{
         kind: relationship.type,
         cardinality: relationship.cardinality,
         source: resource,
         destination: relationship.destination,
         source_attribute: relationship.source_attribute,
         destination_attribute: relationship.destination_attribute,
         joins: [%JoinCondition{child: child, parent: parent}],
         through: nil
       }}
    end
  end

  defp many_to_many_metadata(resource, relationship) do
    through = Map.get(relationship, :through)
    source_join_attribute = Map.get(relationship, :source_attribute_on_join_resource)
    destination_join_attribute = Map.get(relationship, :destination_attribute_on_join_resource)

    cond do
      is_nil(through) or is_nil(source_join_attribute) or is_nil(destination_join_attribute) ->
        {:error,
         Refusal.new(
           :REFUSED_AMBIGUOUS_RELATIONSHIP,
           {resource, relationship.name},
           "many_to_many relationship lacks resolved join-resource metadata",
           %{
             through: through,
             source_attribute_on_join_resource: source_join_attribute,
             destination_attribute_on_join_resource: destination_join_attribute
           }
         )}

      true ->
        with {:ok, source_parent_column} <- column(resource, relationship.source_attribute),
             {:ok, join_source_column} <- column(through, source_join_attribute),
             {:ok, join_destination_column} <- column(through, destination_join_attribute),
             {:ok, destination_parent_column} <- column(relationship.destination, relationship.destination_attribute) do
          {:ok,
           %{
             kind: :many_to_many,
             cardinality: :many,
             source: resource,
             destination: relationship.destination,
             through: through,
             source_attribute: relationship.source_attribute,
             destination_attribute: relationship.destination_attribute,
             source_join_attribute: source_join_attribute,
             destination_join_attribute: destination_join_attribute,
             source_to_join: %JoinCondition{child: source_parent_column, parent: join_source_column},
             join_to_destination: %JoinCondition{child: join_destination_column, parent: destination_parent_column},
             joins: []
           }}
        end
    end
  end

  defp infer_logical_table(resource) do
    data_layer = Ash.Resource.Info.data_layer(resource)

    cond do
      postgres_data_layer?(data_layer) -> infer_postgres_table(resource)
      true ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_LOGICAL_TABLE,
           resource,
           "active Ash data layer does not expose a supported relational logical table; configure an explicit read-only logical table",
           %{data_layer: data_layer}
         )}
    end
  end

  defp postgres_data_layer?(data_layer),
    do: inspect(data_layer) == "AshPostgres.DataLayer"

  defp infer_postgres_table(resource) do
    info = Module.concat([AshPostgres, DataLayer, Info])

    if Code.ensure_loaded?(info) and function_exported?(info, :table, 1) do
      table = apply(info, :table, [resource])
      schema = if function_exported?(info, :schema, 1), do: apply(info, :schema, [resource]), else: nil

      if is_binary(table) and table != "" do
        {:ok, %LogicalTable{table_name: table, schema: schema}}
      else
        {:error,
         Refusal.new(
           :REFUSED_INVALID_LOGICAL_TABLE,
           resource,
           "AshPostgres resource has no concrete table/view identity"
         )}
      end
    else
      {:error,
       Refusal.new(
         :REFUSED_INVALID_LOGICAL_TABLE,
         resource,
         "AshPostgres data layer is selected but its introspection module is unavailable"
       )}
    end
  end
end
