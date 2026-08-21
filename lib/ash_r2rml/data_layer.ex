# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DataLayer do
  @moduledoc """
  Automatic Data Layer Introspection helper for Ash resources.

  Extracts physical database storage details (table name, schema, repo, child/parent join columns)
  directly from active Ash data layers (such as `AshPostgres.DataLayer` or `Ash.DataLayer.Ets`)
  to prevent redundant DSL annotations.
  """

  @doc "Extracts physical relational table name from resource data layer metadata."
  @spec table_name(module()) :: String.t()
  def table_name(resource) when is_atom(resource) do
    cond do
      function_exported?(resource, :ash_postgres_table, 0) ->
        to_string(resource.ash_postgres_table())

      Code.ensure_loaded?(AshPostgres.DataLayer) and function_exported?(AshPostgres.DataLayer, :table, 1) ->
        to_string(apply(AshPostgres.DataLayer, :table, [resource]))

      function_exported?(resource, :table, 0) ->
        to_string(resource.table())

      true ->
        default_table_name(resource)
    end
  rescue
    _ -> default_table_name(resource)
  end

  @doc "Extracts database schema name if configured on data layer."
  @spec schema_name(module()) :: String.t() | nil
  def schema_name(resource) when is_atom(resource) do
    cond do
      function_exported?(resource, :ash_postgres_schema, 0) ->
        to_string(resource.ash_postgres_schema())

      Code.ensure_loaded?(AshPostgres.DataLayer) and function_exported?(AshPostgres.DataLayer, :schema, 1) ->
        to_string(apply(AshPostgres.DataLayer, :schema, [resource]))

      true ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc "Infers relationship join child and parent column names from Ash relationship metadata."
  @spec infer_join_columns(module(), Ash.Resource.Relationships.relationship() | map()) :: {String.t(), String.t()}
  def infer_join_columns(resource, relationship) when is_atom(resource) and is_map(relationship) do
    source_attr =
      Map.get(relationship, :source_attribute) || Map.get(relationship, :source_attribute_on_join_resource) || :id

    dest_attr =
      Map.get(relationship, :destination_attribute) || Map.get(relationship, :destination_attribute_on_join_resource) ||
        :id

    {to_string(source_attr), to_string(dest_attr)}
  end

  defp default_table_name(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Kernel.<>("s")
  end
end
