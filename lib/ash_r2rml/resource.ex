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

  @type t :: %__MODULE__{
          name: atom(),
          form: :select | :construct | :ask | :describe,
          select: [atom()],
          where: term(),
          __identifier__: term(),
          __spark_metadata__: term()
        }
end

defmodule AshR2RML.Dsl.Graph do
  @moduledoc false
  @enforce_keys [:iri]
  defstruct [:iri, :__identifier__, :__spark_metadata__, scope: :resource]
end

defmodule AshR2RML.Resource do
  @moduledoc """
  Spark extension for Ash-first semantic mapping.

  The DSL carries only semantic facts that Ash/data-layer introspection cannot
  prove. Relational table names, attribute source columns, relationship
  destinations, and join attributes are derived whenever possible.
  """

  @class %Spark.Dsl.Entity{
    name: :class,
    describe: "Declares one or more rdf:type class IRIs asserted for every subject of this resource.",
    examples: [
      ~s|class "http://xmlns.com/foaf/0.1/Person"|,
      ~s|class ["http://xmlns.com/foaf/0.1/Person", "http://schema.org/Person"]|
    ],
    args: [:iri],
    target: AshR2RML.Dsl.Class,
    identifier: :iri,
    schema: [iri: [type: {:or, [:string, {:list, :string}]}, required: true]]
  }

  @subject %Spark.Dsl.Entity{
    name: :subject,
    describe:
      "Defines how subject terms are generated: exactly one of template, column, or constant (blank_node term type may omit all).",
    examples: [
      ~s|subject template: "http://example.com/person/{id}"|,
      ~s|subject term_type: :blank_node|
    ],
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
    describe: "Maps an Ash attribute to a predicate-object map with the given predicate IRI.",
    examples: [
      ~s|property :name, "http://xmlns.com/foaf/0.1/name"|,
      ~s|property :age, "http://xmlns.com/foaf/0.1/age", datatype: "http://www.w3.org/2001/XMLSchema#integer"|
    ],
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
    describe: "Maps an Ash relationship to a referencing object map linking subjects via a predicate IRI.",
    examples: [
      ~s|reference :company, "http://example.com/worksFor"|,
      ~s|reference :posts, "http://example.com/authored", direction: :incoming|
    ],
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
    describe: "Assigns generated triples to a named graph IRI, scoped to the whole resource or to the subject map.",
    examples: [
      ~s|graph "http://example.com/graph/people"|,
      ~s|graph "http://example.com/graph/people", scope: :subject|
    ],
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
    describe: "Declares a named SPARQL query (select, construct, ask, or describe) compiled with the resource.",
    examples: [
      ~s|query :all_people, form: :select, select: [:s]|,
      ~s|query :any_person, form: :ask|
    ],
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
    examples: [
      """
      r2rml do
        class "http://xmlns.com/foaf/0.1/Person"
        subject template: "http://example.com/person/{id}"
        property :name, "http://xmlns.com/foaf/0.1/name"
      end
      """
    ],
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
    examples: [
      """
      sparql do
        query :all_people, form: :select, select: [:s]
      end
      """
    ],
    entities: [@sparql_query]
  }

  def section, do: @r2rml

  use Spark.Dsl.Extension,
    sections: [@r2rml, @sparql],
    transformers: [
      AshR2RML.Resource.Persist
    ],
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
    classes = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2RML.Dsl.Class{}, &1))
    subjects = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2RML.Dsl.Subject{}, &1))
    properties = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2RML.Dsl.Property{}, &1))
    references = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2RML.Dsl.Reference{}, &1))
    graphs = Transformer.get_entities(dsl, [:r2rml]) |> Enum.filter(&match?(%AshR2RML.Dsl.Graph{}, &1))

    opts = [
      table_name: Transformer.get_option(dsl, [:r2rml], :table_name, nil),
      sql_query: Transformer.get_option(dsl, [:r2rml], :sql_query, nil),
      schema: Transformer.get_option(dsl, [:r2rml], :schema, nil)
    ]

    with {:ok, logical_table} <- Introspection.logical_table(resource, opts),
         {:ok, subject_map} <- compile_subject(resource, List.first(subjects), graphs),
         {:ok, predicate_object_maps} <- compile_properties(resource, dsl, properties),
         {:ok, reference_object_maps} <- compile_references(resource, dsl, references) do
      dsl_attributes =
        Transformer.get_entities(dsl, [:attributes])
        |> Map.new(fn attribute -> {attribute.name, to_string(Map.get(attribute, :source) || attribute.name)} end)

      ash_attributes =
        Ash.Resource.Info.attributes(resource)
        |> Map.new(fn attribute -> {attribute.name, to_string(attribute.source || attribute.name)} end)

      attribute_columns = Map.merge(dsl_attributes, ash_attributes)

      mapping =
        %Resource{
          ash_resource: resource,
          class_iris: classes |> Enum.flat_map(&List.wrap(&1.iri)) |> Enum.uniq(),
          logical_table: logical_table,
          subject_map: subject_map,
          predicate_object_maps: predicate_object_maps,
          reference_object_maps: reference_object_maps,
          graph_maps: compile_graphs(graphs, :resource),
          identities: Introspection.identities(resource, dsl),
          metadata: %{
            attribute_columns: attribute_columns,
            data_layer: Ash.Resource.Info.data_layer(resource),
            source: :ash_first,
            derived_attributes:
              dsl
              |> derived_names()
              |> Map.take(Enum.map(properties, & &1.attribute))
          }
        }
        |> AshR2RML.Mapping.normalize()

      dsl = Transformer.persist(dsl, :ash_r2rml_public_mapping, mapping)
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

  defp compile_properties(resource, dsl, properties) do
    Enum.reduce_while(properties, {:ok, []}, fn property, {:ok, acc} ->
      case compile_property(resource, dsl, property) do
        {:ok, mapping} -> {:cont, {:ok, [mapping | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> reverse_ok()
  end

  defp compile_property(resource, dsl, property) do
    attribute =
      Ash.Resource.Info.attribute(resource, property.attribute) ||
        find_dsl_attribute(dsl, property.attribute) ||
        find_derived(dsl, property.attribute)

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
      conflict = term_map_conflict(property) ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_TERM_MAP,
           property.attribute,
           "conflicting term map options: #{conflict}"
         )}

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

          {:error, refusal} ->
            {:error, refusal}
        end
    end
  end

  defp term_map_conflict(property) do
    cond do
      is_binary(property.constant) and is_binary(property.template) -> "constant and template"
      property.language && property.datatype -> "language and datatype"
      property.language && property.language_column -> "language and language_column"
      property.language_column && property.datatype -> "language_column and datatype"
      property.datatype && property.term_type in [:iri, :blank_node] -> "datatype with term_type #{property.term_type}"
      true -> nil
    end
  end

  defp compile_references(resource, dsl, references) do
    Enum.reduce_while(references, {:ok, []}, fn reference, {:ok, acc} ->
      rel_result =
        case Introspection.relationship(resource, reference.relationship) do
          {:ok, metadata} ->
            {:ok, metadata}

          {:error, refusal} ->
            if ash_relationship(resource, reference.relationship) do
              {:error, refusal}
            else
              compile_dsl_relationship(resource, dsl, reference.relationship)
            end
        end

      case rel_result do
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

  defp compile_dsl_relationship(resource, dsl, rel_name) do
    rel =
      Transformer.get_entities(dsl, [:relationships])
      |> Enum.find(fn r -> r.name == rel_name end)

    if rel do
      if Map.get(rel, :type) == :many_to_many do
        Introspection.many_to_many_metadata(resource, rel)
      else
        with {:ok, source_attr, dest_attr} <- dsl_join_columns(resource, rel_name, rel) do
          {:ok,
           %{
             kind: rel.type,
             cardinality: Map.get(rel, :cardinality, :one),
             source: resource,
             destination: rel.destination,
             source_attribute: rel.source_attribute,
             destination_attribute: rel.destination_attribute,
             joins: [%AshR2RML.Mapping.JoinCondition{child: source_attr, parent: dest_attr}],
             through: nil
           }}
        end
      end
    else
      {:error,
       Refusal.new(
         :REFUSED_AMBIGUOUS_RELATIONSHIP,
         {resource, rel_name},
         "Ash relationship does not exist"
       )}
    end
  end

  # belongs_to: Ash defaults are source "<rel>_id", destination "id".
  # has_one/has_many: Ash defaults source to :id; the destination attribute is
  # never guessed. Explicit DSL values win, then the compiled Ash relationship,
  # otherwise refuse.
  defp dsl_join_columns(_resource, rel_name, %{type: :belongs_to} = rel) do
    {:ok, to_string(rel.source_attribute || "#{rel_name}_id"), to_string(rel.destination_attribute || "id")}
  end

  defp dsl_join_columns(resource, rel_name, rel) do
    {source, destination} =
      case ash_relationship(resource, rel_name) do
        %{source_attribute: s, destination_attribute: d} -> {rel.source_attribute || s, rel.destination_attribute || d}
        _ -> {rel.source_attribute || :id, rel.destination_attribute}
      end

    if is_nil(destination) do
      {:error,
       Refusal.new(
         :REFUSED_AMBIGUOUS_RELATIONSHIP,
         {resource, rel_name},
         "#{rel.type} relationship has no resolvable destination_attribute; declare it explicitly"
       )}
    else
      {:ok, to_string(source), to_string(destination)}
    end
  end

  defp ash_relationship(resource, rel_name) do
    Ash.Resource.Info.relationship(resource, rel_name)
  rescue
    _ -> nil
  end

  defp compile_graphs(graphs, scope) do
    graphs
    |> Enum.filter(&(&1.scope == scope))
    |> Enum.map(&%GraphMap{strategy: :constant, value: &1.iri})
  end

  defp find_dsl_attribute(dsl, attribute_name) do
    Transformer.get_entities(dsl, [:attributes])
    |> Enum.find(fn attr -> attr.name == attribute_name end)
  end

  # Calculations and aggregates declared locally on this resource, exposed as
  # read-only attribute-like terms. Reads only this resource's own DSL state.
  defp find_derived(dsl, name) do
    calculation =
      Transformer.get_entities(dsl, [:calculations])
      |> Enum.find(&(Map.get(&1, :name) == name))

    aggregate =
      Transformer.get_entities(dsl, [:aggregates])
      |> Enum.find(&(Map.get(&1, :name) == name))

    cond do
      calculation -> %{name: name, type: derived_type(Map.get(calculation, :type)), derived: :calculation}
      aggregate -> %{name: name, type: aggregate_type(aggregate), derived: :aggregate}
      true -> nil
    end
  end

  defp aggregate_type(%{type: type}) when not is_nil(type), do: derived_type(type)
  defp aggregate_type(%{kind: :count}), do: Ash.Type.Integer
  defp aggregate_type(%{kind: :exists}), do: Ash.Type.Boolean
  defp aggregate_type(_), do: nil

  defp derived_type(nil), do: nil
  defp derived_type(type), do: Ash.Type.get_type(type)

  defp derived_names(dsl) do
    for section <- [:calculations, :aggregates],
        entity <- Transformer.get_entities(dsl, [section]),
        into: %{},
        do: {entity.name, section}
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
             Spark.Error.DslError.exception(message: Enum.map_join(refusals, "; ", &"#{&1.code}: #{&1.detail}"))}
        end
    end
  end
end

defmodule AshR2RML.Resource.Info do
  @moduledoc "Public introspection over the normalized mapping IR."

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
      %AshR2RML.Mapping.Resource{} = mapping -> {:ok, mapping}
      _ -> AshR2RML.Resource.LegacyAdapter.convert(resource)
    end
  rescue
    _ -> AshR2RML.Resource.LegacyAdapter.convert(resource)
  end

  def mapping!(resource) do
    case mapping_result(resource) do
      {:ok, mapping} -> mapping
      {:error, refusal} -> raise ArgumentError, "#{refusal.code}: #{refusal.detail}"
    end
  end

  @doc "Resources of an Ash domain that carry the AshR2RML extension."
  @spec domain_resources(module()) :: [module()]
  def domain_resources(domain) do
    domain
    |> Ash.Domain.Info.resources()
    |> Enum.filter(fn resource ->
      extensions = Spark.extensions(resource)
      AshR2RML in extensions or AshR2RML.Resource in extensions
    end)
  end

  @doc "True when the module carries a mapping. Never raises, including on plain Ash resources."
  @spec mapped?(term()) :: boolean()
  def mapped?(resource), do: match?({:ok, _}, fetch_mapping(resource))

  @doc """
  Fetches the mapping for a module without raising.

  Plain Ash resources, non-Spark modules, and non-atoms yield `{:error, :not_mapped}`.
  """
  @spec fetch_mapping(term()) :: {:ok, AshR2RML.Mapping.Resource.t()} | {:error, :not_mapped}
  def fetch_mapping(resource) when is_atom(resource) and not is_nil(resource) do
    case mapping_result(resource) do
      {:ok, %AshR2RML.Mapping.Resource{} = mapping} -> {:ok, mapping}
      _ -> {:error, :not_mapped}
    end
  rescue
    _ -> {:error, :not_mapped}
  end

  def fetch_mapping(_), do: {:error, :not_mapped}

  @spec sparql_queries(module()) :: [AshR2RML.Dsl.SparqlQuery.t()]
  def sparql_queries(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:sparql])
  rescue
    _ -> []
  end
end

defmodule AshR2RML.Resource.LegacyAdapter do
  @moduledoc false

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Introspection

  alias AshR2RML.Mapping.{
    GraphMap,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.Refusal

  def convert(resource) do
    cond do
      function_exported?(resource, :__ash_r2rml_mapping__, 0) ->
        legacy = apply(resource, :__ash_r2rml_mapping__, [])
        convert_legacy(resource, legacy)

      spark_resource?(resource) ->
        class_iri = safe_spark_opt(resource, [:r2rml], :class_iri)
        subject_template = safe_spark_opt(resource, [:r2rml], :subject_template)

        if class_iri && subject_template do
          legacy = %AshR2RML.LegacyMapping{
            resource: resource,
            class_iri: class_iri,
            subject_template: subject_template,
            logical_table:
              case safe_spark_opt(resource, [:r2rml], :table_name) do
                nil -> {:table, "__invalid__"}
                table -> {:table, table}
              end,
            graph_iri: safe_spark_opt(resource, [:r2rml], :graph_iri),
            attributes:
              Enum.map(safe_spark_opt(resource, [:r2rml], :attribute_mappings) || [], fn {attr, pred} ->
                %AshR2RML.AttributeMapping{attribute: attr, column: to_string(attr), predicate_iri: pred}
              end) ++
                Enum.map(safe_spark_opt(resource, [:r2rml], :typed_attribute_mappings) || [], fn {attr, pred, dt} ->
                  %AshR2RML.AttributeMapping{
                    attribute: attr,
                    column: to_string(attr),
                    predicate_iri: pred,
                    datatype_iri: dt
                  }
                end),
            relationships:
              Enum.map(safe_spark_opt(resource, [:r2rml], :relationship_mappings) || [], fn {rel_name, pred} ->
                rel = Ash.Resource.Info.relationship(resource, rel_name)

                source_attr =
                  (rel && (rel.source_attribute || Map.get(rel, :source_attribute))) ||
                    (rel && rel.type == :belongs_to && :"#{rel_name}_id")

                dest_attr = (rel && (rel.destination_attribute || Map.get(rel, :destination_attribute))) || :id

                %AshR2RML.RelationshipMapping{
                  relationship: rel_name,
                  predicate_iri: pred,
                  destination: rel && rel.destination,
                  child_column: source_attr && to_string(source_attr),
                  parent_column: dest_attr && to_string(dest_attr)
                }
              end)
          }

          convert_legacy(resource, legacy)
        else
          {:error,
           Refusal.new(
             :REFUSED_MISSING_SUBJECT_MAP,
             resource,
             "resource has neither the AshR2RML public extension nor a compatibility mapping"
           )}
        end

      true ->
        {:error,
         Refusal.new(
           :REFUSED_MISSING_SUBJECT_MAP,
           resource,
           "resource has neither the AshR2RML public extension nor a compatibility mapping"
         )}
    end
  end

  defp spark_resource?(resource) do
    if is_atom(resource) do
      function_exported?(resource, :spark_is, 0) or
        not is_nil(Spark.Dsl.Extension.get_persisted(resource, :spark_dsl, nil))
    else
      false
    end
  rescue
    _ -> false
  end

  defp safe_spark_opt(resource, path, key) do
    Spark.Dsl.Extension.get_opt(resource, path, key, nil)
  rescue
    _ -> nil
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
              %AshR2RML.Mapping.JoinCondition{
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
       |> AshR2RML.Mapping.normalize()}
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

              error ->
                error
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
