# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.Dsl.Class do
  @moduledoc false
  @enforce_keys [:iri]
  defstruct [:iri]
end

defmodule AshR2ML.Dsl.Subject do
  @moduledoc false
  defstruct [:template, :column, :constant, term_type: :iri]
end

defmodule AshR2ML.Dsl.Property do
  @moduledoc false
  @enforce_keys [:attribute, :predicate_iri]
  defstruct [
    :attribute,
    :predicate_iri,
    :datatype,
    :language,
    :constant,
    :template,
    term_type: :literal
  ]
end

defmodule AshR2ML.Dsl.Reference do
  @moduledoc false
  @enforce_keys [:relationship, :predicate_iri]
  defstruct [:relationship, :predicate_iri, :inverse_predicate]
end

defmodule AshR2ML.Dsl.Graph do
  @moduledoc false
  @enforce_keys [:iri]
  defstruct [:iri, scope: :resource]
end

defmodule AshR2ML.Resource do
  @moduledoc """
  Spark extension for Ash-first semantic mapping.

  The DSL carries only semantic facts that Ash/data-layer introspection cannot
  prove. Relational table names, attribute source columns, relationship
  destinations, and join attributes are derived whenever possible.
  """

  @class %Spark.Dsl.Entity{
    name: :class,
    args: [:iri],
    target: AshR2ML.Dsl.Class,
    identifier: :iri,
    schema: [iri: [type: :string, required: true]]
  }

  @subject %Spark.Dsl.Entity{
    name: :subject,
    target: AshR2ML.Dsl.Subject,
    schema: [
      template: [type: :string],
      column: [type: :atom],
      constant: [type: :string],
      term_type: [type: {:one_of, [:iri, :blank_node]}, default: :iri]
    ]
  }

  @property %Spark.Dsl.Entity{
    name: :property,
    args: [:attribute, :predicate_iri],
    target: AshR2ML.Dsl.Property,
    identifier: :attribute,
    schema: [
      attribute: [type: :atom, required: true],
      predicate_iri: [type: :string, required: true],
      datatype: [type: :string],
      language: [type: :string],
      constant: [type: :string],
      template: [type: :string],
      term_type: [type: {:one_of, [:literal, :iri, :blank_node]}, default: :literal]
    ]
  }

  @reference %Spark.Dsl.Entity{
    name: :reference,
    args: [:relationship, :predicate_iri],
    target: AshR2ML.Dsl.Reference,
    identifier: :relationship,
    schema: [
      relationship: [type: :atom, required: true],
      predicate_iri: [type: :string, required: true],
      inverse_predicate: [type: :string]
    ]
  }

  @graph %Spark.Dsl.Entity{
    name: :graph,
    args: [:iri],
    target: AshR2ML.Dsl.Graph,
    identifier: :iri,
    schema: [
      iri: [type: :string, required: true],
      scope: [type: {:one_of, [:resource, :subject]}, default: :resource]
    ]
  }

  @r2rml %Spark.Dsl.Section{
    name: :r2rml,
    describe: "Semantic mapping metadata normalized into AshR2ML.Mapping",
    schema: [
      table_name: [type: :string],
      sql_query: [type: :string],
      schema: [type: :string]
    ],
    entities: [@class, @subject, @property, @reference, @graph],
    singleton_entity_keys: [:subject]
  }

  use Spark.Dsl.Extension,
    sections: [@r2rml],
    persisters: [AshR2ML.Resource.Persist],
    verifiers: [AshR2ML.Resource.Verify]
end

defmodule AshR2ML.Resource.Persist do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshR2ML.Datatype.Registry
  alias AshR2ML.Introspection
  alias AshR2ML.Mapping.{
    GraphMap,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }
  alias AshR2ML.Refusal
  alias Spark.Dsl.{Transformer, Verifier}

  @impl true
  def transform(dsl) do
    resource = Verifier.get_persisted(dsl, :module)
    classes = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2ML.Dsl.Class{}, &1))
    subjects = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2ML.Dsl.Subject{}, &1))
    properties = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2ML.Dsl.Property{}, &1))
    references = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2ML.Dsl.Reference{}, &1))
    graphs = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2ML.Dsl.Graph{}, &1))

    opts = [
      table_name: Transformer.get_option(dsl, [:r2rml], :table_name, nil),
      sql_query: Transformer.get_option(dsl, [:r2rml], :sql_query, nil),
      schema: Transformer.get_option(dsl, [:r2rml], :schema, nil)
    ]

    with {:ok, logical_table} <- Introspection.logical_table(resource, opts),
         {:ok, subject_map} <- compile_subject(resource, List.first(subjects), graphs),
         {:ok, predicate_object_maps} <- compile_properties(resource, properties),
         {:ok, reference_object_maps} <- compile_references(resource, references) do
      attribute_columns =
        Ash.Resource.Info.attributes(resource)
        |> Map.new(fn attribute -> {attribute.name, to_string(attribute.source || attribute.name)} end)

      mapping =
        %Resource{
          ash_resource: resource,
          class_iris: Enum.map(classes, & &1.iri),
          logical_table: logical_table,
          subject_map: subject_map,
          predicate_object_maps: predicate_object_maps,
          reference_object_maps: reference_object_maps,
          graph_maps: compile_graphs(graphs, :resource),
          identities: Introspection.identities(resource),
          metadata: %{
            attribute_columns: attribute_columns,
            data_layer: Ash.Resource.Info.data_layer(resource),
            source: :ash_first
          }
        }
        |> AshR2ML.Mapping.normalize()

      dsl = Transformer.persist(dsl, :ash_r2ml_public_mapping, mapping)
      {:ok, dsl}
    else
      {:error, %Refusal{} = refusal} -> {:error, refusal.detail}
      {:error, other} -> {:error, inspect(other)}
    end
  end

  defp compile_subject(resource, nil, _graphs) do
    {:error, Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, resource, "r2rml subject mapping is required")}
  end

  defp compile_subject(resource, subject, graphs) do
    configured =
      [
        {:template, subject.template},
        {:column, subject.column},
        {:constant, subject.constant}
      ]
      |> Enum.reject(fn {_strategy, value} -> is_nil(value) end)

    case configured do
      [{:column, attribute}] when is_atom(attribute) ->
        with {:ok, column} <- Introspection.column(resource, attribute) do
          {:ok,
           %SubjectMap{
             strategy: :column,
             value: column,
             term_type: subject.term_type,
             graph_maps: compile_graphs(graphs, :subject)
           }}
        end

      [{strategy, value}] when strategy in [:template, :constant] and is_binary(value) ->
        {:ok,
         %SubjectMap{
           strategy: strategy,
           value: value,
           term_type: subject.term_type,
           graph_maps: compile_graphs(graphs, :subject)
         }}

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_MISSING_SUBJECT_MAP,
           resource,
           "subject requires exactly one of template, column, or constant",
           %{configured: configured}
         )}
    end
  end

  defp compile_properties(resource, properties) do
    Enum.reduce_while(properties, {:ok, []}, fn property, {:ok, acc} ->
      case compile_property(resource, property) do
        {:ok, mapping} -> {:cont, {:ok, [mapping | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> reverse_ok()
  end

  defp compile_property(resource, property) do
    attribute = Ash.Resource.Info.attribute(resource, property.attribute)

    if is_nil(attribute) do
      {:error,
       Refusal.new(
         :REFUSED_UNKNOWN_ATTRIBUTE,
         {resource, property.attribute},
         "property mapping references an unknown Ash attribute"
       )}
    else
      with {:ok, column} <- Introspection.column(resource, property.attribute),
           {:ok, object_map} <- compile_object_map(attribute, column, property) do
        {:ok,
         %PredicateObjectMap{
           attribute: property.attribute,
           predicate_iri: property.predicate_iri,
           object_map: object_map
         }}
      end
    end
  end

  defp compile_object_map(attribute, column, property) do
    {strategy, value} =
      cond do
        is_binary(property.constant) -> {:constant, property.constant}
        is_binary(property.template) -> {:template, property.template}
        true -> {:column, column}
      end

    cond do
      property.language && property.term_type != :literal ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_TERM_MAP,
           property.attribute,
           "language-tagged values must be literal term maps"
         )}

      property.language ->
        {:ok,
         %ObjectMap{
           strategy: strategy,
           value: value,
           language: property.language,
           term_type: :literal
         }}

      property.term_type in [:iri, :blank_node] ->
        {:ok,
         %ObjectMap{
           strategy: strategy,
           value: value,
           term_type: property.term_type
         }}

      true ->
        case Registry.resolve(attribute.type, property.datatype) do
          {:ok, datatype} ->
            {:ok,
             %ObjectMap{
               strategy: strategy,
               value: value,
               datatype: datatype,
               term_type: :literal
             }}

          {:error, refusal} -> {:error, refusal}
        end
    end
  end

  defp compile_references(resource, references) do
    Enum.reduce_while(references, {:ok, []}, fn reference, {:ok, acc} ->
      case Introspection.relationship(resource, reference.relationship) do
        {:ok, metadata} ->
          mapping = %ReferenceObjectMap{
            relationship: reference.relationship,
            predicate_iri: reference.predicate_iri,
            inverse_predicate: reference.inverse_predicate,
            parent_resource: metadata.destination,
            joins: Map.get(metadata, :joins, []),
            metadata: metadata
          }

          {:cont, {:ok, [mapping | acc]}}

        {:error, refusal} ->
          {:halt, {:error, refusal}}
      end
    end)
    |> reverse_ok()
  end

  defp compile_graphs(graphs, scope) do
    graphs
    |> Enum.filter(&(&1.scope == scope))
    |> Enum.map(&%GraphMap{strategy: :constant, value: &1.iri})
  end

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(other), do: other
end

defmodule AshR2ML.Resource.Verify do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    case Verifier.get_persisted(dsl, :ash_r2ml_public_mapping, nil) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "AshR2ML mapping was not persisted; semantic compilation did not complete"
         )}

      mapping ->
        case AshR2ML.Mapping.validate(mapping) do
          :ok -> :ok
          {:error, refusals} ->
            {:error,
             Spark.Error.DslError.exception(
               message: Enum.map_join(refusals, "; ", &"#{&1.code}: #{&1.detail}")
             )}
        end
    end
  end
end

defmodule AshR2ML.Resource.Info do
  @moduledoc "Public introspection over the normalized mapping IR."

  @spec mapping(module()) :: AshR2ML.Mapping.Resource.t() | nil
  def mapping(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, _} -> nil
    end
  end

  @spec mapping_result(module()) ::
          {:ok, AshR2ML.Mapping.Resource.t()} | {:error, AshR2ML.Refusal.t()}
  def mapping_result(resource) do
    persisted = Spark.Dsl.Extension.get_persisted(resource, :ash_r2ml_public_mapping, nil)

    cond do
      match?(%AshR2ML.Mapping.Resource{}, persisted) -> {:ok, persisted}
      true -> AshR2ML.Resource.LegacyAdapter.convert(resource)
    end
  rescue
    _ -> AshR2ML.Resource.LegacyAdapter.convert(resource)
  end

  def mapping!(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, refusal} -> raise ArgumentError, "#{refusal.code}: #{refusal.detail}"
    end
  end
end

defmodule AshR2ML.Resource.LegacyAdapter do
  @moduledoc false

  alias AshR2ML.Datatype.Registry
  alias AshR2ML.Introspection
  alias AshR2ML.Mapping.{
    GraphMap,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }
  alias AshR2ML.Refusal

  def convert(resource) do
    if function_exported?(resource, :__ash_r2ml_mapping__, 0) do
      legacy = apply(resource, :__ash_r2ml_mapping__, [])
      convert_legacy(resource, legacy)
    else
      {:error,
       Refusal.new(
         :REFUSED_MISSING_SUBJECT_MAP,
         resource,
         "resource has neither the AshR2ML public extension nor a compatibility mapping"
       )}
    end
  end

  defp convert_legacy(resource, legacy) do
    with {:ok, properties} <- convert_properties(resource, legacy.attributes) do
      logical_table =
        case legacy.logical_table do
          {:table, table} -> %LogicalTable{table_name: table}
          {:sql_query, query} -> %LogicalTable{sql_query: query}
        end

      references =
        Enum.map(legacy.relationships, fn relationship ->
          %ReferenceObjectMap{
            relationship: relationship.relationship,
            predicate_iri: relationship.predicate_iri,
            parent_resource: relationship.destination,
            joins: [
              %AshR2ML.Mapping.JoinCondition{
                child: relationship.child_column,
                parent: relationship.parent_column
              }
            ],
            metadata: %{kind: :compatibility}
          }
        end)

      graphs =
        if legacy.graph_iri,
          do: [%GraphMap{strategy: :constant, value: legacy.graph_iri}],
          else: []

      attribute_columns =
        Ash.Resource.Info.attributes(resource)
        |> Map.new(fn attribute -> {attribute.name, to_string(attribute.source || attribute.name)} end)

      {:ok,
       %Resource{
         ash_resource: resource,
         class_iris: [legacy.class_iri],
         logical_table: logical_table,
         subject_map: %SubjectMap{strategy: :template, value: legacy.subject_template, term_type: :iri},
         predicate_object_maps: properties,
         reference_object_maps: references,
         graph_maps: graphs,
         identities: Introspection.identities(resource),
         metadata: %{attribute_columns: attribute_columns, source: :compatibility}
       }
       |> AshR2ML.Mapping.normalize()}
    end
  end

  defp convert_properties(resource, attributes) do
    Enum.reduce_while(attributes, {:ok, []}, fn legacy, {:ok, acc} ->
      attribute = Ash.Resource.Info.attribute(resource, legacy.attribute)

      result =
        cond do
          is_nil(attribute) ->
            {:error,
             Refusal.new(
               :REFUSED_UNKNOWN_ATTRIBUTE,
               {resource, legacy.attribute},
               "compatibility mapping references an unknown attribute"
             )}

          true ->
            case Registry.resolve(attribute.type, legacy.datatype_iri) do
              {:ok, datatype} ->
                {:ok,
                 %PredicateObjectMap{
                   attribute: legacy.attribute,
                   predicate_iri: legacy.predicate_iri,
                   object_map: %ObjectMap{
                     strategy: :column,
                     value: legacy.column,
                     datatype: datatype,
                     term_type: :literal
                   }
                 }}

              error -> error
            end
        end

      case result do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end
end
