# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.R2RML do
  @moduledoc """
  Deterministic W3C R2RML renderer over `AshR2RML.Mapping.Bundle`.

  The renderer performs serialization only. All semantic and relational
  decisions must already be explicit in the normalized mapping IR. Term
  validation lives in `AshR2RML.R2RML.Terms`, bridge naming in
  `AshR2RML.R2RML.Identity`, and Turtle quoting in `AshR2RML.R2RML.Turtle`.

  ## Column-valued IRI term maps

  An `rr:column` term map with `term_type: :iri` is rendered verbatim: the column is
  taken to hold a complete IRI. R2RML 7.3 percent-encodes only `rr:template` values, and
  `AshR2RML.OBDA.InMemory` likewise reads such a column as the whole IRI, so the renderer
  and the runtime agree. Existing mappings pin this behavior, so it is not refused.

  ## Example

      {:ok, turtle} = AshR2RML.R2RML.render(MyApp.Person)
  """

  alias AshR2RML.Mapping.{
    Bundle,
    GraphMap,
    LogicalTable,
    ObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.R2RML.Terms
  alias AshR2RML.Refusal

  import AshR2RML.R2RML.Turtle, only: [literal: 1]
  import AshR2RML.R2RML.Identity, only: [bridge_id: 3]

  @prefixes """
  @prefix rr: <http://www.w3.org/ns/r2rml#> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

  """

  @doc """
  Renders a bundle, a single mapping resource, an Ash resource module, or a list of
  Ash resource modules to R2RML Turtle.

  Returns `{:ok, turtle}`, or `{:error, reason}` carrying the first typed
  `AshR2RML.Refusal` from compilation, mapping validation, term validation or rendering.
  """
  @spec render(Bundle.t() | Resource.t() | module() | [module()]) :: {:ok, String.t()} | {:error, term()}
  def render(%Bundle{} = bundle) do
    bundle = AshR2RML.Mapping.normalize(bundle)

    with :ok <- AshR2RML.Mapping.validate(bundle),
         :ok <- Terms.validate(bundle),
         {:ok, body} <- render_bundle(bundle) do
      {:ok, @prefixes <> body}
    end
  end

  def render(%Resource{} = resource) do
    render(%Bundle{resources: [resource]})
  end

  def render(resources) do
    with {:ok, bundle} <- AshR2RML.Compiler.compile_resources(resources) do
      render(bundle)
    end
  end

  defp render_bundle(%Bundle{resources: resources}) do
    by_resource = Map.new(resources, &{&1.ash_resource, &1})

    with {:ok, base_maps} <- collect(resources, &render_resource(&1, by_resource)),
         {:ok, bridge_maps} <- collect_references(resources, by_resource, &bridge_maps/3),
         {:ok, inverse_maps} <- collect_references(resources, by_resource, &inverse_maps/3) do
      rendered =
        (base_maps ++ bridge_maps ++ inverse_maps)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n")

      {:ok, rendered}
    end
  end

  # Short-circuits on the first typed refusal; yields a flat list of rendered bodies.
  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, body} when is_binary(body) -> {:cont, {:ok, [body | acc]}}
        {:ok, bodies} when is_list(bodies) -> {:cont, {:ok, Enum.reverse(bodies, acc)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp collect_references(resources, by_resource, fun) do
    pairs = Enum.flat_map(resources, fn resource -> Enum.map(resource.reference_object_maps, &{resource, &1}) end)

    collect(pairs, fn {resource, reference} -> fun.(resource, reference, by_resource) end)
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
         "<#{triples_map_name(resource)}> a rr:TriplesMap ;\n" <>
           "  rr:logicalTable [ #{render_logical_table(resource.logical_table)} ] ;\n" <>
           "  rr:subjectMap [ #{subject} ]" <>
           predicate_suffix(property_maps ++ ref_maps) <>
           " .\n"}
    end
  end

  defp triples_map_name(%Resource{ash_resource: mod}) when is_atom(mod) and not is_nil(mod) do
    "##{mod |> Module.split() |> Enum.join("_")}"
  end

  defp triples_map_name(resource) do
    AshR2RML.Mapping.mapping_identity(resource)
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
        render_object_term_type(object)

    graph_terms = Enum.flat_map(mapping.graph_maps ++ object.graph_maps, &render_graph_map/1)

    "  rr:predicateObjectMap [ rr:predicate <#{mapping.predicate_iri}>; " <>
      "rr:objectMap [ #{Enum.join(object_terms, "; ")} ]" <>
      pom_graph_suffix(graph_terms) <>
      " ]"
  end

  defp render_reference(%ReferenceObjectMap{} = reference, by_resource) do
    with {:ok, parent} <- fetch_parent(reference, by_resource) do
      joins = Enum.map(reference.joins, &render_join/1)
      object_terms = ["rr:parentTriplesMap <#{triples_map_name(parent)}>" | joins]
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
          "rr:objectMap [ rr:parentTriplesMap <#{triples_map_name(parent)}>; #{render_join(destination_join)} ]" <>
          pom_graph_suffix(graphs) <>
          " ] .\n"

      {:ok, [body]}
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
      graphs = Enum.flat_map(reference.graph_maps, &render_graph_map/1)

      body =
        "<#{id}> a rr:TriplesMap ;\n" <>
          "  rr:logicalTable [ #{render_logical_table(logical_table)} ] ;\n" <>
          "  rr:subjectMap [ #{inverse_subject} ] ;\n" <>
          "  rr:predicateObjectMap [ rr:predicate <#{reference.inverse_predicate}>; " <>
          "rr:objectMap [ rr:parentTriplesMap <#{triples_map_name(resource)}>; #{render_join(source_join)} ]" <>
          pom_graph_suffix(graphs) <>
          " ] .\n"

      {:ok, [body]}
    end
  end

  defp inverse_maps(resource, %ReferenceObjectMap{} = reference, by_resource) do
    with {:ok, parent} <- fetch_parent(reference, by_resource) do
      reversed_joins =
        Enum.map(reference.joins, fn join ->
          %AshR2RML.Mapping.JoinCondition{child: join.parent, parent: join.child}
        end)

      id = bridge_id(resource, reference, "inverse")
      graphs = Enum.flat_map(reference.graph_maps, &render_graph_map/1)

      body =
        "<#{id}> a rr:TriplesMap ;\n" <>
          "  rr:logicalTable [ #{render_logical_table(parent.logical_table)} ] ;\n" <>
          "  rr:subjectMap [ #{render_subject(parent)} ] ;\n" <>
          "  rr:predicateObjectMap [ rr:predicate <#{reference.inverse_predicate}>; " <>
          "rr:objectMap [ rr:parentTriplesMap <#{triples_map_name(resource)}>; " <>
          Enum.map_join(reversed_joins, "; ", &render_join/1) <>
          " ]" <>
          pom_graph_suffix(graphs) <>
          " ] .\n"

      {:ok, [body]}
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
      %LogicalTable{table_name: table} = logical when is_binary(table) and table != "" ->
        {:ok, logical}

      %LogicalTable{sql_query: query} = logical when is_binary(query) and query != "" ->
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
          fields = AshR2RML.Mapping.template_fields(subject.value)

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
       Enum.flat_map(resource.graph_maps ++ subject.graph_maps, &render_graph_map/1))
    |> Enum.join("; ")
  end

  defp bridge_columns(reference, :source) do
    metadata = reference.metadata

    cond do
      Map.has_key?(metadata, :source_parent_column) and
          Map.has_key?(metadata, :source_join_column) ->
        explicit_columns(reference, metadata.source_parent_column, metadata.source_join_column, "source")

      match?(%AshR2RML.Mapping.JoinCondition{}, Map.get(metadata, :source_to_join)) ->
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
        explicit_columns(
          reference,
          metadata.destination_parent_column,
          metadata.destination_join_column,
          "destination"
        )

      match?(%AshR2RML.Mapping.JoinCondition{}, Map.get(metadata, :join_to_destination)) ->
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

  defp explicit_columns(_reference, parent, join, _side)
       when is_binary(parent) and parent != "" and is_binary(join) and join != "",
       do: {:ok, {parent, join}}

  defp explicit_columns(reference, parent, join, side) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_JOIN_CONDITION,
       reference.relationship,
       "many_to_many #{side} bridge columns must be non-empty strings",
       %{parent_column: parent, join_column: join}
     )}
  end

  defp bridge_join(reference, :source) do
    with {:ok, {parent, child}} <- bridge_columns(reference, :source) do
      {:ok, %AshR2RML.Mapping.JoinCondition{child: child, parent: parent}}
    end
  end

  defp bridge_join(reference, :destination) do
    with {:ok, {parent, child}} <- bridge_columns(reference, :destination) do
      {:ok, %AshR2RML.Mapping.JoinCondition{child: child, parent: parent}}
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

  defp render_object_term_map(%ObjectMap{strategy: :constant, term_type: :literal, language: language, value: value})
       when is_binary(language),
       do: "rr:constant #{literal(value)}@#{language}"

  defp render_object_term_map(%ObjectMap{
         strategy: :constant,
         term_type: :literal,
         datatype: %{rdf_datatype: datatype},
         value: value
       })
       when is_binary(datatype),
       do: "rr:constant #{literal(value)}^^<#{datatype}>"

  defp render_object_term_map(%ObjectMap{strategy: :constant, term_type: :literal, value: value}),
    do: "rr:constant #{literal(value)}"

  defp render_object_term_map(%ObjectMap{strategy: :template, value: value}),
    do: "rr:template #{literal(value)}"

  defp render_object_term_map(%ObjectMap{strategy: :column, value: value}),
    do: "rr:column #{literal(value)}"

  defp render_object_datatype(%ObjectMap{strategy: :constant}), do: []

  # W3C R2RML 7.3: rr:datatype and rr:language are valid only on literal term maps.
  defp render_object_datatype(%ObjectMap{term_type: term_type}) when term_type != :literal, do: []

  defp render_object_datatype(%ObjectMap{language: language}) when is_binary(language),
    do: ["rr:language #{literal(language)}"]

  defp render_object_datatype(%ObjectMap{datatype: %{rdf_datatype: iri}}) when is_binary(iri),
    do: ["rr:datatype <#{iri}>"]

  defp render_object_datatype(_), do: []

  # rr:template defaults to rr:IRI, so a literal template object map must say so explicitly.
  defp render_object_term_type(%ObjectMap{strategy: :template, term_type: :literal}),
    do: ["rr:termType rr:Literal"]

  defp render_object_term_type(%ObjectMap{term_type: term_type}), do: render_term_type(term_type, :object)

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

  defp unwrap({:ok, value}), do: value
end
