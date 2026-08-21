# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PersistMapping do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshR2RML.{AttributeMapping, RelationshipMapping}
  alias Spark.Dsl.{Transformer, Verifier}

  @impl true
  def after?(Ash.Resource.Transformers.CachePrimaryKey), do: true
  def after?(Ash.Resource.Transformers.DefaultPrimaryKey), do: true
  def after?(Ash.Resource.Transformers.SetRelationshipInformation), do: true
  def after?(Ash.Resource.Transformers.BelongsToAttribute), do: true
  def after?(Ash.Resource.Transformers.BelongsToSourceAttribute), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    table_name = Transformer.get_option(dsl, [:r2rml], :table_name, nil)
    sql_query = Transformer.get_option(dsl, [:r2rml], :sql_query, nil)

    logical_table =
      case {table_name, sql_query} do
        {table, nil} when is_binary(table) -> {:table, table}
        {nil, query} when is_binary(query) -> {:sql_query, query}
        {table, _query} when is_binary(table) -> {:table, table}
        _ -> {:table, "__invalid_r2rml_logical_table__"}
      end

    attributes =
      Transformer.get_option(dsl, [:r2rml], :attribute_mappings, [])
      |> Enum.map(fn {attribute, predicate_iri} ->
        %AttributeMapping{
          attribute: attribute,
          column: column_for_attribute(resource, attribute),
          predicate_iri: predicate_iri
        }
      end)

    typed_attributes =
      Transformer.get_option(dsl, [:r2rml], :typed_attribute_mappings, [])
      |> Enum.map(fn {attribute, predicate_iri, datatype_iri} ->
        %AttributeMapping{
          attribute: attribute,
          column: column_for_attribute(resource, attribute),
          predicate_iri: predicate_iri,
          datatype_iri: datatype_iri
        }
      end)

    relationships =
      Transformer.get_option(dsl, [:r2rml], :relationship_mappings, [])
      |> Enum.map(fn {relationship_name, predicate_iri} ->
        rel_from_info =
          try do
            Ash.Resource.Info.relationship(resource, relationship_name)
          rescue
            _ -> nil
          end

        dsl_rel =
          rel_from_info ||
            Transformer.get_entities(dsl, [:relationships])
            |> Enum.find(&(&1.name == relationship_name))

        source_attr =
          (dsl_rel && Map.get(dsl_rel, :source_attribute)) ||
            (dsl_rel && Map.get(dsl_rel, :type) == :belongs_to && :"#{relationship_name}_id")

        dest_attr =
          (dsl_rel && Map.get(dsl_rel, :destination_attribute)) || :id

        destination = dsl_rel && Map.get(dsl_rel, :destination)

        %RelationshipMapping{
          relationship: relationship_name,
          predicate_iri: predicate_iri,
          destination: destination,
          child_column: source_attr && to_string(source_attr),
          parent_column: dest_attr && to_string(dest_attr)
        }
      end)

    mapping = %AshR2RML.LegacyMapping{
      resource: resource,
      class_iri: Transformer.get_option(dsl, [:r2rml], :class_iri),
      subject_template: Transformer.get_option(dsl, [:r2rml], :subject_template),
      logical_table: logical_table,
      graph_iri: Transformer.get_option(dsl, [:r2rml], :graph_iri, nil),
      attributes: attributes ++ typed_attributes,
      relationships: relationships
    }

    {:ok,
     Transformer.eval(
       dsl,
       [],
       quote do
         @doc false
         def __ash_r2rml_mapping__, do: unquote(Macro.escape(mapping))
       end
     )}
  end

  defp column_for_attribute(_resource, nil), do: nil

  defp column_for_attribute(resource, attribute_name) do
    case Ash.Resource.Info.attribute(resource, attribute_name) do
      nil -> to_string(attribute_name)
      attribute -> to_string(attribute.source || attribute.name)
    end
  end
end
