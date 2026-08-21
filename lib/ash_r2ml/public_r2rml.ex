# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.R2RML do
  @moduledoc """
  Deterministic W3C R2RML renderer over `AshR2ML.Mapping.Bundle`.

  The renderer performs serialization only. All semantic and relational
  decisions must already be explicit in the normalized mapping IR.
  """

  alias AshR2ML.Mapping.{
    Bundle,
    GraphMap,
    LogicalTable,
    ObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2ML.Refusal

  @prefixes """@prefix rr: <http://www.w3.org/ns/r2rml#> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

"""

  @spec render(Bundle.t() | module() | [module()]) :: {:ok, String.t()} | {:error, term()}
  def render(%Bundle{} = bundle) do
    bundle = AshR2ML.Mapping.normalize(bundle)

    with :ok <- AshR2ML.Mapping.validate(bundle),
         {:ok, body} <- render_bundle(bundle) do
      {:ok, @prefixes <> body}
    end
  end

  def render(resources) do
    with {:ok, bundle} <- AshR2ML.Compiler.compile_resources(resources) do
      render(bundle)
    end
  end

  defp render_bundle(%Bundle{resources: resources}) do
    by_resource = Map.new(resources, &{&1.ash_resource, &1})
    base_maps = Enum.map(resources, &render_resource(&1, by_resource))

    bridge_maps =
      Enum.flat_map(resources, fn resource ->
        Enum.flat_map(resource.reference_object_maps, fn reference ->
          case bridge_maps(resource, reference, by_resource) do
            {:ok, values} -> values
            {:error, refusal} -> [{:error, refusal}]
          end
        end)
      end)

    inverse_maps =
      Enum.flat_map(resources, fn resource ->
        Enum.flat_map(resource.reference_object_maps, fn reference ->
          case inverse_maps(resource, reference, by_resource) do
            {:ok, values} -> values
            {:error, refusal} -> [{:error, refusal}]
          end
        end)
      end)

    all = base_maps ++ bridge_maps ++ inverse_maps

    case Enum.find(all, &match?({:error, _}, &1)) do
      {:error, refusal} ->
        {:error, refusal}

      nil ->
        rendered =
          all
          |> Enum.map(&unwrap/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        {:ok, rendered}
    end
  end

  defp render_resource(%Resource{} = resource, by_resource) do
    references =
      resource.reference_object_maps
      |> Enum.reject(&(Map.get(&1.metadata, :kind) == :many_to_many))
      |> Enum.map(&render_reference(&1, by_resource))

    case Enum.find(references, &match?({:error, _}, &1)) do
      {:error, refusal} ->
        {:error, refusal}

      nil ->
        property_maps = Enum.map(resource.predicate_object_maps, &render_property/1)
        ref_maps = Enum.map(references, &unwrap/1)
        subject = render_subject(resource)

        {:ok,
         "<#{AshR2ML.Mapping.mapping_identity(resource)}> a rr:TriplesMap ;\n" <>
           "  rr:logicalTable [ #{render_logical_table(resource.logical_table)} ] ;\n" <>
           "  rr:subjectMap [ #{subject} ]" <>
           predicate_suffix(property_maps ++ ref_maps) <>
           " .\n"}
    end
  end

  defp render_subject(resource) do
    subject = resource.subject_map

    ([render_subject_term_map(subject)] ++
       Enum.map(resource.class_iris, &"rr:class <#{&1}>") ++
       render_term_type(subject.term_type, :subject) ++
       Enum.flat_map(resource.graph_maps ++ subject.graph_maps, &render_graph_map/1))
    |> Enum.join("; ")
  end

  defp render_property(mapping) do
    object = mapping.object_map

    object_terms =
      [render_object_term_map(object)] ++
        render_object_datatype(object) ++
        render_term_type(object.term_type, :object)

    graph_terms = Enum.flat_map(mapping.graph_maps ++ object.graph_maps, &render_graph_map/1)

    "  rr:predicateObjectMap [ rr:predicate <#{mapping.predicate_iri}>; " <>
      "rr:objectMap [ #{Enum.join(object_terms, "; ")} ]" <>
      pom_graph_suffix(graph_terms) <>
      " ]"
  end

  defp render_reference(%ReferenceObjectMap{} = reference, by_resource) do
    case Map.get(by_resource, reference.parent_resource) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
           reference.relationship,
           "reference parent mapping is absent from bundle",
           %{parent_resource: reference.parent_resource}
         )}

      parent ->
        joins = Enum.map(reference.joins, &render_join/1)
        object_terms = ["rr:parentTriplesMap <#{AshR2ML.Mapping.mapping_identity(parent)}>" | joins]
        graphs = Enum.flat_map(reference.graph_maps, &render_graph_map/1)

        {:ok,
         "  rr:predicateObjectMap [ rr:predicate <#{reference.predicate_iri}>; " <>
           "rr:objectMap [ #{Enum.join(object_terms, "; ")} ]" <>
           pom_graph_suffix(graphs) <>
           " ]"}
    end
  end

  defp bridge_maps(_resource, %ReferenceObjectMap{metadata: metadata}, _by_resource)
       when not is_map_key(metadata, :kind),
       do: {:ok, []}

  defp bridge_maps(
         resource,
         %ReferenceObjectMap{metadata: %{kind: :many_to_many}} = reference,
         by_resource
       ) do
    with {:ok, parent} <- fetch_parent(reference, by_resource),
         {:ok, logical_table} <- through_logical_table(reference),
         {:ok, bridge_subject} <- bridge_subject(resource, reference, :source),
         {:ok, destination_join} <- bridge_join(reference, :destination) do
      id = bridge_id(resource, reference, "forward")
      graphs = Enum.flat_map(reference.graph_maps, &render_graph_map/1)

      body =
        "<#{id}> a rr:TriplesMap ;\n" <>
          "  rr:logicalTable [ #{render_logical_table(logical_table)} ] ;\n" <>
          "  rr:subjectMap [ #{bridge_subject} ] ;\n" <>
          "  rr:predicateObjectMap [ rr:predicate <#{reference.predicate_iri}>; " <>
          "rr:objectMap [ rr:parentTriplesMap <#{AshR2ML.Mapping.mapping_identity(parent)}>; #{render_join(destination_join)} ]" <>
          pom_graph_suffix(graphs) <>
          " ] .\n"

      {:ok, [{:ok, body}]}
    end
  end

  defp bridge_maps(_resource, _reference, _by_resource), do: {:ok, []}

  defp inverse_maps(_resource, %ReferenceObjectMap{inverse_predicate: nil}, _by_resource),
    do: {:ok, []}

  defp inverse_maps(
         resource,
         %ReferenceObjectMap{metadata: %{kind: :many_to_many}} = reference,
         by_resource
       ) do
    with {:ok, parent} <- fetch_parent(reference, by_resource),
         {:ok, logical_table} <- through_logical_table(reference),
         {:ok, inverse_subject} <- bridge_subject(parent, reference, :destination),
         {:ok, source_join} <- bridge_join(reference, :source) do
      id = bridge_id(resource, reference, "inverse")

      body =
        "<#{id}> a rr:TriplesMap ;\n" <>
          "  rr:logicalTable [ #{render_logical_table(logical_table)} ] ;\n" <>
          "  rr:subjectMap [ #{inverse_subject} ] ;\n" <>
          "  rr:predicateObjectMap [ rr:predicate <#{reference.inverse_predicate}>; " <>
          "rr:objectMap [ rr:parentTriplesMap <#{AshR2ML.Mapping.mapping_identity(resource)}>; #{render_join(source_join)} ] ] .\n"

      {:ok, [{:ok, body}]}
    end
  end

  defp inverse_maps(resource, %ReferenceObjectMap{} = reference, by_resource) do
    with {:ok, parent} <- fetch_parent(reference, by_resource) do
      reversed_joins =
        Enum.map(reference.joins, fn join ->
          %AshR2ML.Mapping.JoinCondition{child: join.parent, parent: join.child}
        end)

      id = bridge_id(resource, reference, "inverse")

      body =
        "<#{id}> a rr:TriplesMap ;\n" <>
          "  rr:logicalTable [ #{render_logical_table(parent.logical_table)} ] ;\n" <>
          "  rr:subjectMap [ #{render_subject(parent)} ] ;\n" <>
          "  rr:predicateObjectMap [ rr:predicate <#{reference.inverse_predicate}>; " <>
          "rr:objectMap [ rr:parentTriplesMap <#{AshR2ML.Mapping.mapping_identity(resource)}>; " <>
          Enum.map_join(reversed_joins, "; ", &render_join/1) <>
          " ] ] .\n"

      {:ok, [{:ok, body}]}
    end
  end

  defp fetch_parent(reference, by_resource) do
    case Map.get(by_resource, reference.parent_resource) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
           reference.relationship,
           "reference parent mapping is absent from bundle",
           %{parent_resource: reference.parent_resource}
         )}

      parent ->
        {:ok, parent}
    end
  end

  defp through_logical_table(reference) do
    case Map.get(reference.metadata, :through_logical_table) do
      %LogicalTable{} = logical ->
        {:ok, logical}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_LOGICAL_TABLE,
           reference.relationship,
           "many_to_many mapping lacks normalized through logical table",
           %{through_logical_table: other}
         )}
    end
  end

  defp bridge_subject(resource, reference, side) do
    with {:ok, {parent_column, join_column}} <- bridge_columns(reference, side) do
      subject = resource.subject_map

      case subject.strategy do
        :template ->
          fields = AshR2ML.Mapping.template_fields(subject.value)

          if parent_column in fields do
            remapped = String.replace(subject.value, "{#{parent_column}}", "{#{join_column}}")
            {:ok, render_bridge_subject_map(subject, remapped, resource)}
          else
            {:error,
             Refusal.new(
               :REFUSED_MISSING_SUBJECT_MAP,
               {resource.ash_resource, reference.relationship},
               "many_to_many bridge cannot remap subject template because source identity column is absent",
               %{template: subject.value, identity_column: parent_column}
             )}
          end

        :column ->
          if subject.value == parent_column do
            {:ok, render_bridge_subject_map(subject, join_column, resource)}
          else
            {:error,
             Refusal.new(
               :REFUSED_MISSING_SUBJECT_MAP,
               {resource.ash_resource, reference.relationship},
               "many_to_many bridge column subject does not use the joined source identity",
               %{subject_column: subject.value, identity_column: parent_column}
             )}
          end

        :constant ->
          {:ok, render_bridge_subject_map(subject, subject.value, resource)}

        other ->
          {:error,
           Refusal.new(
             :UNSUPPORTED_TERM_TYPE,
             {resource.ash_resource, reference.relationship},
             "subject strategy is unsupported for many_to_many bridge mapping",
             %{strategy: other}
           )}
      end
    end
  end

  defp render_bridge_subject_map(%SubjectMap{} = subject, value, resource) do
    bridge_subject = %{subject | value: value}

    ([render_subject_term_map(bridge_subject)] ++
       render_term_type(subject.term_type, :subject) ++
       Enum.flat_map(resource.graph_maps, &render_graph_map/1))
    |> Enum.join("; ")
  end

  defp bridge_columns(reference, :source) do
    metadata = reference.metadata

    cond do
      Map.has_key?(metadata, :source_parent_column) and
          Map.has_key?(metadata, :source_join_column) ->
        {:ok, {metadata.source_parent_column, metadata.source_join_column}}

      match?(%AshR2ML.Mapping.JoinCondition{}, Map.get(metadata, :source_to_join)) ->
        join = metadata.source_to_join
        {:ok, {join.child, join.parent}}

      true ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_JOIN_CONDITION,
           reference.relationship,
           "many_to_many source bridge columns are incomplete"
         )}
    end
  end

  defp bridge_columns(reference, :destination) do
    metadata = reference.metadata

    cond do
      Map.has_key?(metadata, :destination_parent_column) and
          Map.has_key?(metadata, :destination_join_column) ->
        {:ok, {metadata.destination_parent_column, metadata.destination_join_column}}

      match?(%AshR2ML.Mapping.JoinCondition{}, Map.get(metadata, :join_to_destination)) ->
        join = metadata.join_to_destination
        {:ok, {join.parent, join.child}}

      true ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_JOIN_CONDITION,
           reference.relationship,
           "many_to_many destination bridge columns are incomplete"
         )}
    end
  end

  defp bridge_join(reference, :source) do
    with {:ok, {parent, child}} <- bridge_columns(reference, :source) do
      {:ok, %AshR2ML.Mapping.JoinCondition{child: child, parent: parent}}
    end
  end

  defp bridge_join(reference, :destination) do
    with {:ok, {parent, child}} <- bridge_columns(reference, :destination) do
      {:ok, %AshR2ML.Mapping.JoinCondition{child: child, parent: parent}}
    end
  end

  defp render_logical_table(%LogicalTable{table_name: table, schema: schema})
       when is_binary(table) do
    qualified = if is_binary(schema) and schema != "", do: schema <> "." <> table, else: table
    "rr:tableName #{literal(qualified)}"
  end

  defp render_logical_table(%LogicalTable{sql_query: query}) when is_binary(query),
    do: "rr:sqlQuery #{literal(query)}"

  defp render_subject_term_map(%SubjectMap{strategy: :template, value: value}),
    do: "rr:template #{literal(value)}"

  defp render_subject_term_map(%SubjectMap{strategy: :column, value: value}),
    do: "rr:column #{literal(value)}"

  defp render_subject_term_map(%SubjectMap{strategy: :constant, value: value}),
    do: "rr:constant <#{value}>"

  defp render_subject_term_map(%SubjectMap{strategy: :blank_node, value: value}),
    do: "rr:template #{literal(value)}"

  defp render_object_term_map(%ObjectMap{strategy: :constant, term_type: :iri, value: value}),
    do: "rr:constant <#{value}>"

  defp render_object_term_map(
         %ObjectMap{strategy: :constant, term_type: :literal, language: language, value: value}
       )
       when is_binary(language),
       do: "rr:constant #{literal(value)}@#{language}"

  defp render_object_term_map(
         %ObjectMap{
           strategy: :constant,
           term_type: :literal,
           datatype: %{rdf_datatype: datatype},
           value: value
         }
       )
       when is_binary(datatype),
       do: "rr:constant #{literal(value)}^^<#{datatype}>"

  defp render_object_term_map(%ObjectMap{strategy: :constant, term_type: :literal, value: value}),
    do: "rr:constant #{literal(value)}"

  defp render_object_term_map(%ObjectMap{strategy: :template, value: value}),
    do: "rr:template #{literal(value)}"

  defp render_object_term_map(%ObjectMap{strategy: :column, value: value}),
    do: "rr:column #{literal(value)}"

  defp render_object_datatype(%ObjectMap{strategy: :constant}), do: []

  defp render_object_datatype(%ObjectMap{language: language}) when is_binary(language),
    do: ["rr:language #{literal(language)}"]

  defp render_object_datatype(%ObjectMap{datatype: %{rdf_datatype: iri}}) when is_binary(iri),
    do: ["rr:datatype <#{iri}>"]

  defp render_object_datatype(_), do: []

  defp render_term_type(:literal, _scope), do: []
  defp render_term_type(:iri, :subject), do: []
  defp render_term_type(:iri, :object), do: ["rr:termType rr:IRI"]
  defp render_term_type(:blank_node, _scope), do: ["rr:termType rr:BlankNode"]

  defp render_graph_map(%GraphMap{strategy: :constant, value: value}),
    do: ["rr:graph <#{value}>"]

  defp render_graph_map(%GraphMap{strategy: :template, value: value}),
    do: ["rr:graphMap [ rr:template #{literal(value)} ]"]

  defp render_graph_map(%GraphMap{strategy: :column, value: value}),
    do: ["rr:graphMap [ rr:column #{literal(value)} ]"]

  defp render_join(join),
    do: "rr:joinCondition [ rr:child #{literal(join.child)}; rr:parent #{literal(join.parent)} ]"

  defp predicate_suffix([]), do: ""
  defp predicate_suffix(values), do: ";\n" <> Enum.join(values, ";\n")
  defp pom_graph_suffix([]), do: ""
  defp pom_graph_suffix(values), do: "; " <> Enum.join(values, "; ")

  defp bridge_id(resource, reference, direction) do
    payload =
      {AshR2ML.Mapping.mapping_identity(resource), reference.relationship, reference.predicate_iri,
       direction}
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "urn:ash-r2ml:bridge:" <> payload
  end

  defp literal(value) do
    escaped =
      value
      |> to_string()
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\r", "\\r")
      |> String.replace("\n", "\\n")

    "\"#{escaped}\""
  end

  defp unwrap({:ok, value}), do: value
end
