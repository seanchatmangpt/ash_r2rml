# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

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
  alias Spark.Dsl.Transformer

  @impl true
  def after?(Ash.Resource.Transformers.CachePrimaryKey), do: true
  def after?(Ash.Resource.Transformers.DefaultPrimaryKey), do: true
  def after?(Ash.Resource.Transformers.SetRelationshipInformation), do: true
  def after?(Ash.Resource.Transformers.BelongsToAttribute), do: true
  def after?(Ash.Resource.Transformers.BelongsToSourceAttribute), do: true
  def after?(_), do: false

  # Every Ash/Spark lookup below receives `dsl`, never the module atom: the
  # module is still compiling while transformers run.
  @impl true
  def transform(dsl) do
    resource = Transformer.get_persisted(dsl, :module)
    grouped = entities_by_kind(dsl)
    properties = Map.get(grouped, AshR2RML.Dsl.Property, [])
    graphs = Map.get(grouped, AshR2RML.Dsl.Graph, [])
    subject = grouped |> Map.get(AshR2RML.Dsl.Subject, []) |> List.first()

    with {:ok, logical_table} <- Introspection.logical_table(resource, table_options(dsl)),
         {:ok, subject_map} <- compile_subject(resource, dsl, subject, graphs),
         {:ok, property_maps} <- compile_properties(resource, dsl, properties),
         {:ok, temporal_maps} <- compile_temporals(dsl, Map.get(grouped, AshR2RML.Dsl.Temporal, [])),
         {:ok, reference_object_maps} <-
           compile_references(resource, dsl, Map.get(grouped, AshR2RML.Dsl.Reference, [])) do
      mapping =
        build_mapping(dsl, resource, grouped, %{
          logical_table: logical_table,
          subject_map: subject_map,
          predicate_object_maps: property_maps ++ temporal_maps,
          reference_object_maps: reference_object_maps
        })

      {:ok, Transformer.persist(dsl, :ash_r2rml_public_mapping, mapping)}
    else
      {:error, %Refusal{} = refusal} -> {:error, refusal.detail}
      {:error, other} -> {:error, inspect(other)}
    end
  end

  defp entities_by_kind(dsl) do
    dsl
    |> Transformer.get_entities([:r2rml])
    |> Enum.group_by(& &1.__struct__)
  end

  defp table_options(dsl) do
    [
      table_name: Transformer.get_option(dsl, [:r2rml], :table_name, nil),
      sql_query: Transformer.get_option(dsl, [:r2rml], :sql_query, nil),
      schema: Transformer.get_option(dsl, [:r2rml], :schema, nil),
      dsl: dsl
    ]
  end

  defp build_mapping(dsl, resource, grouped, compiled) do
    classes = Map.get(grouped, AshR2RML.Dsl.Class, [])
    properties = Map.get(grouped, AshR2RML.Dsl.Property, [])
    graphs = Map.get(grouped, AshR2RML.Dsl.Graph, [])

    %Resource{
      ash_resource: resource,
      class_iris: classes |> Enum.flat_map(&List.wrap(&1.iri)) |> Enum.uniq(),
      logical_table: compiled.logical_table,
      subject_map: compiled.subject_map,
      predicate_object_maps: compiled.predicate_object_maps,
      reference_object_maps: compiled.reference_object_maps,
      graph_maps: compile_graphs(graphs, :resource),
      identities: Introspection.identities(dsl),
      metadata: %{
        attribute_columns: attribute_columns(dsl),
        data_layer: Ash.DataLayer.data_layer(dsl),
        source: :ash_first,
        derived_attributes:
          dsl
          |> derived_names()
          |> Map.take(Enum.map(properties, & &1.attribute))
      }
    }
    |> AshR2RML.Mapping.normalize()
  end

  defp attribute_columns(dsl) do
    dsl
    |> Ash.Resource.Info.attributes()
    |> Map.new(fn attribute -> {attribute.name, to_string(attribute.source || attribute.name)} end)
  end

  defp compile_subject(resource, _dsl, nil, _graphs) do
    {:error, Refusal.new(:REFUSED_MISSING_SUBJECT_MAP, resource, "r2rml subject mapping is required")}
  end

  defp compile_subject(resource, dsl, subject, graphs) do
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
        with {:ok, column} <- Introspection.column(dsl, attribute) do
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

  defp compile_temporals(dsl, temporals) do
    lookup = fn name ->
      with %{type: type} <- Introspection.attribute(dsl, name),
           {:ok, column} <- Introspection.column(dsl, name) do
        {:ok, type, column}
      else
        _ -> :error
      end
    end

    Enum.reduce_while(temporals, {:ok, []}, fn temporal, {:ok, acc} ->
      case AshR2RML.Temporal.compile(temporal, lookup) do
        {:ok, maps} -> {:cont, {:ok, acc ++ maps}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp compile_property(resource, dsl, property) do
    with {:ok, attribute, column} <- resolve_term(resource, dsl, property.attribute),
         :ok <- reject_range(attribute, property),
         {:ok, object_map} <- compile_object_map(attribute, column, property) do
      {:ok,
       %PredicateObjectMap{
         attribute: property.attribute,
         predicate_iri: property.predicate_iri,
         object_map: object_map
       }}
    end
  end

  # A stored attribute resolves to its source column (refusing when Ash cannot
  # name one); a locally declared calculation/aggregate is read-only and is
  # addressed by its own name.
  defp resolve_term(resource, dsl, name) do
    case Introspection.attribute(dsl, name) do
      nil ->
        case find_derived(dsl, name) do
          nil ->
            {:error,
             Refusal.new(
               :REFUSED_UNKNOWN_ATTRIBUTE,
               {resource, name},
               "property mapping references an unknown Ash attribute"
             )}

          derived ->
            {:ok, derived, to_string(name)}
        end

      attribute ->
        with {:ok, column} <- Introspection.column(dsl, name) do
          {:ok, attribute, column}
        end
    end
  end

  defp reject_range(attribute, property) do
    if is_nil(property.datatype) and AshR2RML.Temporal.range_type?(Map.get(attribute, :type)) do
      {:error, AshR2RML.Temporal.range_refusal(attribute.type, property.attribute)}
    else
      :ok
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
        case Introspection.relationship(resource, reference.relationship, dsl) do
          {:ok, metadata} ->
            {:ok, metadata}

          {:error, refusal} ->
            if Ash.Resource.Info.relationship(dsl, reference.relationship) do
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
        Introspection.many_to_many_metadata(resource, rel, dsl)
      else
        with {:ok, source_attr, dest_attr} <- dsl_join_columns(resource, dsl, rel_name, rel) do
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
  defp dsl_join_columns(_resource, _dsl, rel_name, %{type: :belongs_to} = rel) do
    {:ok, to_string(rel.source_attribute || "#{rel_name}_id"), to_string(rel.destination_attribute || "id")}
  end

  defp dsl_join_columns(resource, dsl, rel_name, rel) do
    {source, destination} =
      case Ash.Resource.Info.relationship(dsl, rel_name) do
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

  defp compile_graphs(graphs, scope) do
    graphs
    |> Enum.filter(&(&1.scope == scope))
    |> Enum.map(&%GraphMap{strategy: :constant, value: &1.iri})
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

  defp derived_names(dsl) do
    for section <- [:calculations, :aggregates],
        entity <- Transformer.get_entities(dsl, [section]),
        into: %{},
        do: {entity.name, section}
  end

  defp derived_type(nil), do: nil
  defp derived_type(type), do: Ash.Type.get_type(type)

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(other), do: other
end
