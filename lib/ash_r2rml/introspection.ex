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

  @doc """
  Resolves the logical table of a resource.

  Pass `dsl: dsl` while the resource is still compiling so data-layer facts are
  read from the DSL state instead of the not-yet-compiled module.
  """
  @spec logical_table(module(), keyword()) :: {:ok, LogicalTable.t()} | {:error, Refusal.t()}
  def logical_table(resource, opts \\ []) do
    explicit_table = blank_to_nil(Keyword.get(opts, :table_name))
    explicit_query = blank_to_nil(Keyword.get(opts, :sql_query))
    explicit_schema = blank_to_nil(Keyword.get(opts, :schema))

    case {explicit_table, explicit_query} do
      {table, nil} when is_binary(table) ->
        {:ok, %LogicalTable{table_name: table, schema: explicit_schema}}

      {nil, query} when is_binary(query) and is_nil(explicit_schema) ->
        {:ok, %LogicalTable{sql_query: query}}

      {nil, nil} ->
        infer_logical_table(resource, Keyword.get(opts, :dsl))

      {nil, query} when is_binary(query) ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_LOGICAL_TABLE,
           resource,
           "schema cannot be combined with sql_query"
         )}

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_LOGICAL_TABLE,
           resource,
           "exactly one of table_name or sql_query may be configured"
         )}
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      _ -> value
    end
  end

  defp blank_to_nil(value), do: value

  @doc """
  Looks up an attribute on a compiled resource or on a Spark DSL state.

  Returns `nil` for a nil name, an unknown name, or a module that is not an Ash resource.
  """
  @spec attribute(module() | map(), atom() | nil) :: struct() | nil
  def attribute(_resource, nil), do: nil

  def attribute(resource, name) when is_atom(name) do
    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.find(&(&1.name == name))
  rescue
    UndefinedFunctionError -> nil
  end

  def attribute(_resource, _name), do: nil

  @doc """
  Source column of an attribute (`source || name`).

  Refuses with `:REFUSED_UNKNOWN_ATTRIBUTE` when the attribute is missing or nil;
  a column is never guessed from the attribute name.
  """
  @spec column(module() | map(), atom() | nil) :: {:ok, String.t()} | {:error, Refusal.t()}
  def column(resource, attribute_name) do
    case attribute(resource, attribute_name) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           {owner(resource), attribute_name},
           "attribute does not exist on the resource; no source column can be derived"
         )}

      attr ->
        {:ok, source_column(attr)}
    end
  end

  defp source_column(attr), do: to_string(attr.source || attr.name)

  defp owner(dsl) when is_map(dsl), do: Spark.Dsl.Transformer.get_persisted(dsl, :module)
  defp owner(resource), do: resource

  @doc """
  Classifies an attribute for monetary projection.

  `:money` for AshMoney-style types (detected by module name, no dependency),
  `:decimal` for `Ash.Type.Decimal`, `:none` otherwise. A hand-written
  `AshR2RML.Type` value object is `:composite`; `AshR2RML.Money.project/2`
  accepts its `{:node, ...}` output or refuses with a typed refusal.
  """
  @spec monetary_kind(module(), atom()) :: {:ok, :money | :decimal | :composite | :none}
  def monetary_kind(resource, attribute_name) when is_atom(attribute_name) do
    case Ash.Resource.Info.attribute(resource, attribute_name) do
      nil -> {:ok, :none}
      %{type: type} -> {:ok, classify_money(AshR2RML.Datatype.Registry.unwrap(type) |> elem(0))}
    end
  end

  defp classify_money(type) do
    cond do
      AshR2RML.Money.money_type?(type) -> :money
      type == Ash.Type.Decimal -> :decimal
      composite_value_object?(type) -> :composite
      true -> :none
    end
  end

  defp composite_value_object?(type) do
    match?({:ok, %{semantic_kind: :value_object}}, AshR2RML.Type.contract(type))
  end

  @doc """
  Globally unique key sets of a resource (compiled module or Spark DSL state).

    * the primary key
    * each declared identity without a `where` clause; a partial identity is
      unique only inside its predicate, so it never proves global subject uniqueness
    * under `:attribute` multitenancy, an identity with `all_tenants?: false` is
      unique per tenant only, so the tenant attribute is added to its keys: a subject
      template must carry the tenant attribute or it is refused as unstable, which
      rejects cross-tenant subject IRI collisions at compile time
    * under `:context` (schema) multitenancy the same key can exist in every tenant
      schema, so neither the primary key nor an ordinary identity is globally unique;
      only an identity declared `all_tenants?: true` is kept. A resource with no such
      identity yields `[]` and its subject template is refused as unstable
  """
  @spec identities(module() | map()) :: [[atom()]]
  def identities(source), do: extract_identities(source, tenancy(source))

  defp extract_identities(source, tenancy) do
    primary =
      case tenancy do
        :context ->
          []

        _ ->
          source
          |> Ash.Resource.Info.attributes()
          |> Enum.filter(&Map.get(&1, :primary_key?))
          |> Enum.map(& &1.name)
      end

    declared =
      source
      |> Ash.Resource.Info.identities()
      |> Enum.reject(&partial_identity?/1)
      |> Enum.filter(&(tenancy != :context or Map.get(&1, :all_tenants?, false)))
      |> Enum.map(&scope_to_tenant(List.wrap(&1.keys), Map.get(&1, :all_tenants?, false), tenancy))

    [primary | declared]
    |> Enum.reject(&(&1 == []))
    |> Enum.map(&Enum.sort/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp partial_identity?(identity), do: not is_nil(Map.get(identity, :where))

  defp tenancy(source) do
    case Ash.Resource.Info.multitenancy_strategy(source) do
      :attribute -> Ash.Resource.Info.multitenancy_attribute(source)
      :context -> :context
      _ -> nil
    end
  end

  defp scope_to_tenant(keys, true, _tenancy), do: keys
  defp scope_to_tenant(keys, _all_tenants?, nil), do: keys
  defp scope_to_tenant(keys, _all_tenants?, tenant), do: Enum.uniq(keys ++ [tenant])

  @doc """
  True when the subject template's columns are exactly one globally unique key set
  of `resource` (see `identities/1`). A column that maps to no attribute is never stable.
  """
  @spec stable_subject_identity?(module(), [String.t()]) :: boolean()
  def stable_subject_identity?(resource, template_fields) do
    columns_by_attribute =
      resource
      |> Ash.Resource.Info.attributes()
      |> Map.new(fn attribute -> {source_column(attribute), attribute.name} end)

    template_keys = Enum.map(template_fields, &Map.get(columns_by_attribute, &1))

    Enum.all?(template_keys, &(not is_nil(&1))) and
      Enum.any?(identities(resource), &(MapSet.new(&1) == MapSet.new(template_keys)))
  end

  @doc """
  Relationship metadata for `resource`. While the resource is compiling, pass its
  DSL state as `source` so lookups never touch the uncompiled module.
  """
  @spec relationship(module(), atom(), module() | map() | nil) :: {:ok, map()} | {:error, Refusal.t()}
  def relationship(resource, relationship_name, source \\ nil) do
    source = source || resource

    case Ash.Resource.Info.relationship(source, relationship_name) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_AMBIGUOUS_RELATIONSHIP,
           {resource, relationship_name},
           "Ash relationship does not exist"
         )}

      relationship ->
        relationship_metadata(resource, source, relationship)
    end
  end

  defp relationship_metadata(resource, source, relationship) do
    case Map.get(relationship, :type) do
      :many_to_many ->
        many_to_many_metadata(resource, relationship, source)

      type when type in [:belongs_to, :has_one, :has_many] ->
        simple_relationship_metadata(resource, source, relationship)

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

  defp simple_relationship_metadata(resource, source, relationship) do
    with {:ok, child} <- column(source, relationship.source_attribute),
         {:ok, parent} <- destination_column(relationship.destination, relationship.destination_attribute) do
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

  # A destination resource that is still compiling (cyclic resource graphs) cannot be read yet;
  # its column is then the attribute name, and a compiled destination refuses unknown attributes.
  defp destination_column(destination, attribute_name) do
    case Ash.Resource.Info.attributes(destination) do
      attributes when is_list(attributes) -> column(destination, attribute_name)
    end
  rescue
    RuntimeError -> {:ok, to_string(attribute_name)}
    ArgumentError -> {:ok, to_string(attribute_name)}
    UndefinedFunctionError -> {:ok, to_string(attribute_name)}
  end

  @doc false
  def many_to_many_metadata(resource, relationship, source \\ nil) do
    source = source || resource
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
        with {:ok, source_parent_column} <- column(source, relationship.source_attribute),
             {:ok, join_source_column} <- column(through, source_join_attribute),
             {:ok, join_destination_column} <- column(through, destination_join_attribute),
             {:ok, destination_parent_column} <- column(relationship.destination, relationship.destination_attribute),
             {:ok, through_table} <- logical_table(through) do
          {:ok,
           %{
             kind: :many_to_many,
             cardinality: :many,
             source: resource,
             destination: relationship.destination,
             through: through,
             through_logical_table: through_table,
             source_attribute: relationship.source_attribute,
             destination_attribute: relationship.destination_attribute,
             source_join_attribute: source_join_attribute,
             destination_join_attribute: destination_join_attribute,
             source_parent_column: source_parent_column,
             source_join_column: join_source_column,
             destination_join_column: join_destination_column,
             destination_parent_column: destination_parent_column,
             source_to_join: %JoinCondition{child: source_parent_column, parent: join_source_column},
             join_to_destination: %JoinCondition{child: join_destination_column, parent: destination_parent_column},
             joins: []
           }}
        end
    end
  end

  # While compiling (dsl given) nothing is persisted yet; read the DSL state only.
  defp infer_logical_table(resource, nil) do
    case persisted_logical_table(resource) do
      %LogicalTable{} = logical -> {:ok, logical}
      nil -> infer_logical_table_from_data_layer(resource, resource)
    end
  end

  defp infer_logical_table(resource, dsl), do: infer_logical_table_from_data_layer(resource, dsl)

  defp persisted_logical_table(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_public_mapping, nil) do
      %AshR2RML.Mapping.Resource{logical_table: %LogicalTable{} = logical} -> logical
      _ -> nil
    end
  rescue
    # Only a module that is not (yet) a Spark resource has no persisted state.
    UndefinedFunctionError -> nil
    ArgumentError -> nil
  end

  defp infer_logical_table_from_data_layer(resource, source) do
    data_layer = Ash.Resource.Info.data_layer(source)

    if postgres_data_layer?(data_layer) do
      infer_postgres_table(resource, source)
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

  # ash_postgres is an optional/test-only dep; compare by name to avoid a compile-time reference.
  defp postgres_data_layer?(data_layer), do: data_layer == Module.concat(["AshPostgres", "DataLayer"])

  defp infer_postgres_table(resource, source) do
    # ash_postgres is an optional/test-only dep; dispatch dynamically to avoid a compile-time reference.
    info = Module.concat(["AshPostgres", "DataLayer", "Info"])

    if Code.ensure_loaded?(info) do
      table = info.table(source)
      schema = info.schema(source)

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
