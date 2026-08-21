# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Introspection do
  @moduledoc """
  Data-layer-aware Ash introspection used before semantic mapping serialization.

  Ash is authoritative for compiled resource identity and relationship semantics.
  This module never guesses an unknown attribute column or reconstructs a
  compiled primary key from partially transformed Spark entities.
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
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           {resource, attribute_name},
           "column introspection requires a compiled Ash attribute; refusing guessed storage name"
         )}

      attribute ->
        {:ok, to_string(attribute.source || attribute.name)}
    end
  end

  def column(resource, attribute_name) do
    {:error,
     Refusal.new(
       :REFUSED_UNKNOWN_ATTRIBUTE,
       {resource, attribute_name},
       "column introspection requires an Ash attribute name"
     )}
  end

  @doc "Returns compiled Ash identity keys as attribute names."
  @spec identities(module() | Spark.Dsl.t(), Spark.Dsl.t() | nil) :: [[atom()]]
  def identities(resource_or_dsl, dsl \\ nil)

  def identities(%{__struct__: Spark.Dsl} = dsl, _ignored) do
    # A raw Spark DSL has not crossed Ash's compiled semantic boundary. Preserve
    # explicitly declared identities only; do not infer a primary key from
    # `primary_key?` attribute flags here.
    Spark.Dsl.Transformer.get_entities(dsl, [:identities])
    |> Enum.map(&List.wrap(&1.keys))
    |> normalize_identities()
  end

  def identities(resource, _dsl) when is_atom(resource) do
    primary = List.wrap(Ash.Resource.Info.primary_key(resource))

    declared =
      if function_exported?(Ash.Resource.Info, :identities, 1) do
        Ash.Resource.Info.identities(resource)
        |> Enum.map(&List.wrap(&1.keys))
      else
        []
      end

    [primary | declared]
    |> normalize_identities()
  rescue
    _ -> []
  end

  @doc "Translates every compiled Ash identity into its physical source-column identity."
  @spec identity_columns(module()) :: [[String.t()]]
  def identity_columns(resource) do
    Enum.reduce(identities(resource), [], fn identity, acc ->
      case map_identity_columns(resource, identity) do
        {:ok, columns} -> [columns | acc]
        {:error, _} -> acc
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp map_identity_columns(resource, identity) do
    identity
    |> Enum.reduce_while({:ok, []}, fn attribute, {:ok, acc} ->
      case column(resource, attribute) do
        {:ok, source} -> {:cont, {:ok, [source | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, columns} -> {:ok, Enum.reverse(columns)}
      error -> error
    end
  end

  @spec stable_subject_identity?(module(), [String.t()]) :: boolean()
  def stable_subject_identity?(resource, template_fields) do
    fields = MapSet.new(template_fields)
    fields != MapSet.new() and Enum.any?(identity_columns(resource), &(MapSet.new(&1) == fields))
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
      :many_to_many -> many_to_many_metadata(resource, relationship)
      type when type in [:belongs_to, :has_one, :has_many] -> simple_relationship_metadata(resource, relationship)
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

  defp normalize_identities(values) do
    values
    |> Enum.reject(&(&1 == []))
    |> Enum.map(&Enum.sort/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
