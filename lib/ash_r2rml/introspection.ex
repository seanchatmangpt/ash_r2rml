# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Introspection do
  @moduledoc """
  Data-layer-aware Ash introspection used before semantic mapping serialization.

  AshR2RML never owns persistence. This module asks Ash and, when present, the
  active relational data layer for table/schema/column/join facts. Optional
  adapters are resolved dynamically so AshPostgres is not a mandatory runtime
  dependency merely to use the semantic core.
  """

  alias AshR2RML.Mapping.{JoinCondition, LogicalTable}
  alias AshR2RML.Refusal

  @spec logical_table(module(), keyword()) :: {:ok, LogicalTable.t()} | {:error, Refusal.t()}
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
  def column(resource, attribute_name) when is_atom(attribute_name) do
    case Ash.Resource.Info.attribute(resource, attribute_name) do
      nil -> {:ok, to_string(attribute_name)}
      attribute -> {:ok, to_string(attribute.source || attribute.name)}
    end
  end

  @spec identities(module() | Spark.Dsl.t(), Spark.Dsl.t() | nil) :: [[atom()]]
  def identities(resource_or_dsl, dsl \\ nil)

  def identities(%{__struct__: Spark.Dsl} = dsl, _nil) do
    extract_identities(nil, dsl)
  end

  def identities(resource, dsl) do
    extract_identities(resource, dsl)
  end

  defp extract_identities(resource, dsl) do
    primary_from_ash = if resource, do: List.wrap(Ash.Resource.Info.primary_key(resource)), else: []

    primary_from_dsl =
      if dsl,
        do:
          Spark.Dsl.Transformer.get_entities(dsl, [:attributes])
          |> Enum.filter(&Map.get(&1, :primary_key?))
          |> Enum.map(& &1.name),
        else: []

    primary = Enum.uniq(primary_from_ash ++ primary_from_dsl)

    declared =
      cond do
        resource && function_exported?(Ash.Resource.Info, :identities, 1) ->
          Ash.Resource.Info.identities(resource)
          |> Enum.map(&List.wrap(&1.keys))

        dsl ->
          Spark.Dsl.Transformer.get_entities(dsl, [:identities])
          |> Enum.map(&List.wrap(&1.keys))

        true ->
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

    template_keys = Enum.map(template_fields, &Map.get(columns_by_attribute, &1))

    Enum.all?(template_keys, &is_atom/1) and
      Enum.any?(identities(resource), &(MapSet.new(&1) == MapSet.new(template_keys)))
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
    case Map.get(relationship, :type) do
      :many_to_many ->
        many_to_many_metadata(resource, relationship)

      type when type in [:belongs_to, :has_one, :has_many] ->
        simple_relationship_metadata(resource, relationship)

      type ->
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
         cardinality: Map.get(relationship, :cardinality),
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
    case persisted_logical_table(resource) do
      %LogicalTable{} = logical -> {:ok, logical}
      nil -> infer_logical_table_from_data_layer(resource)
    end
  end

  defp persisted_logical_table(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_public_mapping, nil) do
      %AshR2RML.Mapping.Resource{logical_table: %LogicalTable{} = logical} -> logical
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp infer_logical_table_from_data_layer(resource) do
    data_layer = Ash.Resource.Info.data_layer(resource)

    if inspect(data_layer) == "AshPostgres.DataLayer" do
      infer_postgres_table(resource)
    else
      {:error,
       Refusal.new(
         :REFUSED_INVALID_LOGICAL_TABLE,
         resource,
         "active Ash data layer does not expose a supported relational logical table; configure an explicit read-only logical table",
         %{data_layer: data_layer}
       )}
    end
  end

  defp infer_postgres_table(resource) do
    info = Module.concat(["AshPostgres", "DataLayer", "Info"])

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
