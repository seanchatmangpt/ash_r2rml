# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Dsl.Class do
  @moduledoc false
  @enforce_keys [:iri]
  defstruct [:iri, :__identifier__, :__spark_metadata__]
end

defmodule AshR2RML.Dsl.Subject do
  @moduledoc false
  defstruct [:template, :column, :constant, :__identifier__, :__spark_metadata__, term_type: :iri]
end

defmodule AshR2RML.Dsl.Property do
  @moduledoc false
  @enforce_keys [:attribute, :predicate_iri]
  defstruct [
    :attribute,
    :predicate_iri,
    :datatype,
    :language,
    :language_column,
    :constant,
    :template,
    :__identifier__,
    :__spark_metadata__,
    term_type: :literal
  ]
end

defmodule AshR2RML.Dsl.Reference do
  @moduledoc false
  @enforce_keys [:relationship, :predicate_iri]
  defstruct [
    :relationship,
    :predicate_iri,
    :inverse_predicate,
    :guard_class,
    :__identifier__,
    :__spark_metadata__,
    direction: :outgoing
  ]
end

defmodule AshR2RML.Dsl.SparqlQuery do
  @moduledoc false
  @enforce_keys [:name]
  defstruct [:name, form: :select, select: [], where: [], __identifier__: nil, __spark_metadata__: nil]
end

defmodule AshR2RML.Dsl.Graph do
  @moduledoc false
  @enforce_keys [:iri]
  defstruct [:iri, :__identifier__, :__spark_metadata__, scope: :resource]
end

defmodule AshR2RML.Resource do
  @moduledoc """
  Canonical Spark extension for Ash-first semantic mapping.

  The DSL carries only semantic facts that Ash/data-layer introspection cannot
  prove. Every successful compile persists exactly one normalized
  `AshR2RML.Mapping.Resource` under `:ash_r2rml_public_mapping`.
  """

  @class %Spark.Dsl.Entity{
    name: :class,
    args: [:iri],
    target: AshR2RML.Dsl.Class,
    identifier: :iri,
    schema: [iri: [type: {:or, [:string, {:list, :string}]}, required: true]]
  }

  @subject %Spark.Dsl.Entity{
    name: :subject,
    target: AshR2RML.Dsl.Subject,
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
    target: AshR2RML.Dsl.Property,
    identifier: :attribute,
    schema: [
      attribute: [type: :atom, required: true],
      predicate_iri: [type: :string, required: true],
      datatype: [type: :string],
      language: [type: :string],
      language_column: [type: :atom],
      constant: [type: :string],
      template: [type: :string],
      term_type: [type: {:one_of, [:literal, :iri, :blank_node]}, default: :literal]
    ]
  }

  @reference %Spark.Dsl.Entity{
    name: :reference,
    args: [:relationship, :predicate_iri],
    target: AshR2RML.Dsl.Reference,
    identifier: :relationship,
    schema: [
      relationship: [type: :atom, required: true],
      predicate_iri: [type: :string, required: true],
      inverse_predicate: [type: :string],
      direction: [type: {:one_of, [:outgoing, :incoming]}, default: :outgoing],
      guard_class: [type: :string]
    ]
  }

  @graph %Spark.Dsl.Entity{
    name: :graph,
    args: [:iri],
    target: AshR2RML.Dsl.Graph,
    identifier: :iri,
    schema: [
      iri: [type: :string, required: true],
      scope: [type: {:one_of, [:resource, :subject]}, default: :resource]
    ]
  }

  @sparql_query %Spark.Dsl.Entity{
    name: :query,
    args: [:name],
    target: AshR2RML.Dsl.SparqlQuery,
    identifier: :name,
    schema: [
      name: [type: :atom, required: true],
      form: [type: {:one_of, [:select, :construct, :ask, :describe]}, default: :select],
      select: [type: {:list, :atom}, default: []],
      where: [type: :any, default: []]
    ]
  }

  @r2rml %Spark.Dsl.Section{
    name: :r2rml,
    describe: "Semantic mapping metadata normalized into AshR2RML.Mapping",
    schema: [
      table_name: [type: :string],
      sql_query: [type: :string],
      schema: [type: :string]
    ],
    entities: [@class, @subject, @property, @reference, @graph],
    singleton_entity_keys: [:subject]
  }

  @sparql %Spark.Dsl.Section{
    name: :sparql,
    describe: "Declarative SPARQL query definitions compiled with the resource",
    entities: [@sparql_query]
  }

  def section, do: @r2rml

  use Spark.Dsl.Extension,
    sections: [@r2rml, @sparql],
    transformers: [AshR2RML.Resource.Persist],
    verifiers: [AshR2RML.Resource.Verify],
    single_extension_kinds: [:ash_r2rml]
end

defmodule AshR2RML.Resource.Persist do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Introspection

  alias AshR2RML.Mapping.{
    GraphMap,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.Refusal
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
    classes = entities(dsl, AshR2RML.Dsl.Class)
    subjects = entities(dsl, AshR2RML.Dsl.Subject)
    properties = entities(dsl, AshR2RML.Dsl.Property)
    references = entities(dsl, AshR2RML.Dsl.Reference)
    graphs = entities(dsl, AshR2RML.Dsl.Graph)

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
          class_iris: classes |> Enum.flat_map(&List.wrap(&1.iri)) |> Enum.uniq(),
          logical_table: logical_table,
          subject_map: subject_map,
          predicate_object_maps: predicate_object_maps,
          reference_object_maps: reference_object_maps,
          graph_maps: compile_graphs(graphs, :resource),
          identities: Introspection.identities(resource),
          metadata: %{
            attribute_columns: attribute_columns,
            identity_columns: Introspection.identity_columns(resource),
            data_layer: Ash.Resource.Info.data_layer(resource),
            source: :ash_first
          }
        }
        |> AshR2RML.Mapping.normalize()

      {:ok, Transformer.persist(dsl, :ash_r2rml_public_mapping, mapping)}
    else
      {:error, %Refusal{} = refusal} -> {:error, refusal.detail}
      {:error, other} -> {:error, inspect(other)}
    end
  end

  defp entities(dsl, module) do
    Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%{__struct__: ^module}, &1))
  end

  defp compile_subject(resource, nil, _graphs) do
    {:error, Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, resource, "r2rml subject mapping is required")}
  end

  defp compile_subject(resource, subject, graphs) do
    configured =
      [template: subject.template, column: subject.column, constant: subject.constant]
      |> Enum.reject(fn {_strategy, value} -> is_nil(value) end)

    case {subject.term_type, configured} do
      {:blank_node, []} ->
        {:ok,
         %SubjectMap{
           strategy: :blank_node,
           value: "bnode_{id}",
           term_type: :blank_node,
           graph_maps: compile_graphs(graphs, :subject)
         }}

      {:blank_node, [{:template, value}]} ->
        {:ok,
         %SubjectMap{
           strategy: :blank_node,
           value: value,
           term_type: :blank_node,
           graph_maps: compile_graphs(graphs, :subject)
         }}

      {_term_type, [{:column, attribute}]} when is_atom(attribute) ->
        with {:ok, column} <- Introspection.column(resource, attribute) do
          {:ok,
           %SubjectMap{
             strategy: :column,
             value: column,
             term_type: subject.term_type,
             graph_maps: compile_graphs(graphs, :subject)
           }}
        end

      {_term_type, [{strategy, value}]} when strategy in [:template, :constant] and is_binary(value) ->
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
    properties
    |> Enum.reduce_while({:ok, []}, fn property, {:ok, acc} ->
      case compile_property(resource, property) do
        {:ok, mapping} -> {:cont, {:ok, [mapping | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> reverse_ok()
  end

  defp compile_property(resource, property) do
    case Ash.Resource.Info.attribute(resource, property.attribute) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           {resource, property.attribute},
           "property mapping references an unknown compiled Ash attribute"
         )}

      attribute ->
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

      property.language_column ->
        {:ok,
         %ObjectMap{
           strategy: strategy,
           value: value,
           language: to_string(property.language_column),
           term_type: :literal
         }}

      property.term_type in [:iri, :blank_node] ->
        {:ok, %ObjectMap{strategy: strategy, value: value, term_type: property.term_type}}

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

          {:error, refusal} ->
            {:error, refusal}
        end
    end
  end

  defp compile_references(resource, references) do
    references
    |> Enum.reduce_while({:ok, []}, fn reference, {:ok, acc} ->
      case Introspection.relationship(resource, reference.relationship) do
        {:ok, metadata} ->
          mapping = %ReferenceObjectMap{
            relationship: reference.relationship,
            predicate_iri: reference.predicate_iri,
            inverse_predicate: reference.inverse_predicate,
            parent_resource: metadata.destination,
            joins: Map.get(metadata, :joins, []),
            metadata: Map.merge(metadata, %{direction: reference.direction, guard_class: reference.guard_class})
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

defmodule AshR2RML.Resource.Verify do
  @moduledoc false
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    case Verifier.get_persisted(dsl, :ash_r2rml_public_mapping, nil) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message: "AshR2RML mapping was not persisted; semantic compilation did not complete"
         )}

      mapping ->
        case AshR2RML.Mapping.validate(mapping) do
          :ok ->
            :ok

          {:error, refusals} ->
            {:error,
             Spark.Error.DslError.exception(
               message: Enum.map_join(refusals, "; ", &"#{&1.code}: #{&1.detail}")
             )}
        end
    end
  end
end

defmodule AshR2RML.Resource.Info do
  @moduledoc "Public fail-closed introspection over the single persisted normalized mapping IR."

  @spec mapping(module()) :: AshR2RML.Mapping.Resource.t() | nil
  def mapping(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, _} -> nil
    end
  end

  @spec mapping_result(module()) ::
          {:ok, AshR2RML.Mapping.Resource.t()} | {:error, AshR2RML.Refusal.t()}
  def mapping_result(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_public_mapping, nil) do
      %AshR2RML.Mapping.Resource{} = mapping ->
        {:ok, mapping}

      observed ->
        {:error,
         AshR2RML.Refusal.new(
           :REFUSED_MISSING_SUBJECT_MAP,
           resource,
           "resource has no canonical persisted AshR2RML mapping; compatibility conversion is not an ambient compiler path",
           %{persisted_mapping: inspect(observed)}
         )}
    end
  rescue
    error ->
      {:error,
       AshR2RML.Refusal.new(
         :REFUSED_MISSING_SUBJECT_MAP,
         resource,
         "canonical persisted AshR2RML mapping could not be read",
         %{exception: Exception.message(error)}
       )}
  end

  def mapping!(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, refusal} -> raise ArgumentError, "#{refusal.code}: #{refusal.detail}"
    end
  end

  def mapped?(resource), do: match?({:ok, _}, mapping_result(resource))

  @deprecated "Neo4j control is not an AshR2RML mapping capability; use mapped?/1"
  def neo4j_control_present?(resource), do: mapped?(resource)

  @spec sparql_queries(module()) :: [AshR2RML.Dsl.SparqlQuery.t()]
  def sparql_queries(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:sparql])
  rescue
    _ -> []
  end
end
