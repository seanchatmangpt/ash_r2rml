# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Graph do
  @moduledoc false
  alias AshR2ml.Resource.Info

  def closure(resources) do
    resources
    |> List.wrap()
    |> do_closure(MapSet.new(), [])
  end

  defp do_closure([], _seen, acc),
    do: {:ok, Enum.sort_by(acc, &Atom.to_string/1)}

  defp do_closure([resource | rest], seen, acc) do
    if MapSet.member?(seen, resource) do
      do_closure(rest, seen, acc)
    else
      case Info.mapping(resource) do
        nil ->
          {:error, {:unmapped_resource, resource}}

        mapping ->
          destinations = Enum.map(mapping.relationships, & &1.destination)

          case Enum.find(destinations, &(not Info.mapped?(&1))) do
            nil ->
              do_closure(
                rest ++ destinations,
                MapSet.put(seen, resource),
                [resource | acc]
              )

            destination ->
              relationship = Enum.find(mapping.relationships, &(&1.destination == destination))
              {:error, {:unmapped_destination, resource, relationship.relationship, destination}}
          end
      end
    end
  end
end

defmodule AshR2ml.R2RML do
  @moduledoc "Deterministic W3C R2RML Turtle renderer over AshR2ml mappings."

  alias AshR2ml.{Graph, Resource}

  @prefixes """@prefix rr: <http://www.w3.org/ns/r2rml#> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

"""

  def render(resources) do
    with {:ok, closure} <- Graph.closure(resources) do
      body = closure |> Enum.map_join("\n", &render_mapping(Resource.Info.mapping!(&1)))
      {:ok, @prefixes <> body}
    end
  end

  defp render_mapping(mapping) do
    id = triples_map_id(mapping.resource)

    [
      "<##{id}> a rr:TriplesMap ;\n",
      "  rr:logicalTable [ ", logical_table(mapping.logical_table), " ] ;\n",
      "  rr:subjectMap [ rr:template ", literal(mapping.subject_template),
      "; rr:class <", mapping.class_iri, ">", graph_fragment(mapping.graph_iri), " ]",
      predicate_object_maps(mapping),
      " .\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp logical_table({:table, table}), do: "rr:tableName #{literal(table)}"
  defp logical_table({:sql_query, query}), do: "rr:sqlQuery #{literal(query)}"

  defp graph_fragment(nil), do: ""
  defp graph_fragment(iri), do: "; rr:graph <#{iri}>"

  defp predicate_object_maps(mapping) do
    attrs = Enum.map(mapping.attributes, &render_attribute/1)
    rels = Enum.map(mapping.relationships, &render_relationship/1)

    case attrs ++ rels do
      [] -> ""
      maps -> ";\n" <> Enum.join(maps, ";\n")
    end
  end

  defp render_attribute(attribute) do
    datatype =
      if attribute.datatype_iri,
        do: "; rr:datatype <#{attribute.datatype_iri}>",
        else: ""

    "  rr:predicateObjectMap [ rr:predicate <#{attribute.predicate_iri}>; " <>
      "rr:objectMap [ rr:column #{literal(attribute.column)}#{datatype} ] ]"
  end

  defp render_relationship(relationship) do
    parent = triples_map_id(relationship.destination)

    "  rr:predicateObjectMap [ rr:predicate <#{relationship.predicate_iri}>; " <>
      "rr:objectMap [ rr:parentTriplesMap <##{parent}>; " <>
      "rr:joinCondition [ rr:child #{literal(relationship.child_column)}; " <>
      "rr:parent #{literal(relationship.parent_column)} ] ] ]"
  end

  defp triples_map_id(resource), do: resource |> Module.split() |> Enum.join("_")

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
end

defmodule AshR2ml.SHACL do
  @moduledoc "SHACL projection derived from the same AshR2ml mapping IR."

  alias AshR2ml.{Graph, Resource}

  @prefixes """@prefix sh: <http://www.w3.org/ns/shacl#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

"""

  def render(resources) do
    with {:ok, closure} <- Graph.closure(resources) do
      body = closure |> Enum.map_join("\n", &render_shape(Resource.Info.mapping!(&1)))
      {:ok, @prefixes <> body}
    end
  end

  defp render_shape(mapping) do
    properties =
      Enum.map(mapping.attributes, &attribute_shape(mapping.resource, &1)) ++
        Enum.map(mapping.relationships, &relationship_shape/1)

    suffix =
      case properties do
        [] -> ""
        list -> ";\n" <> Enum.join(list, ";\n")
      end

    "<urn:ash-r2ml:shape:#{shape_id(mapping.resource)}> a sh:NodeShape ;\n" <>
      "  sh:targetClass <#{mapping.class_iri}>#{suffix} .\n"
  end

  defp attribute_shape(resource, mapping) do
    attribute = Ash.Resource.Info.attribute(resource, mapping.attribute)
    required = if attribute && attribute.allow_nil? == false, do: "; sh:minCount 1", else: ""
    datatype = mapping.datatype_iri || datatype_for(attribute && attribute.type)
    datatype_clause = if datatype, do: "; sh:datatype <#{datatype}>", else: ""

    "  sh:property [ sh:path <#{mapping.predicate_iri}>#{required}#{datatype_clause} ]"
  end

  defp relationship_shape(mapping) do
    destination = Resource.Info.mapping!(mapping.destination)

    "  sh:property [ sh:path <#{mapping.predicate_iri}>; sh:nodeKind sh:IRI; " <>
      "sh:class <#{destination.class_iri}> ]"
  end

  defp datatype_for(nil), do: nil

  defp datatype_for(type) do
    case Ash.Type.get_type(type) do
      Ash.Type.String -> "http://www.w3.org/2001/XMLSchema#string"
      Ash.Type.Integer -> "http://www.w3.org/2001/XMLSchema#integer"
      Ash.Type.Float -> "http://www.w3.org/2001/XMLSchema#double"
      Ash.Type.Decimal -> "http://www.w3.org/2001/XMLSchema#decimal"
      Ash.Type.Boolean -> "http://www.w3.org/2001/XMLSchema#boolean"
      Ash.Type.Date -> "http://www.w3.org/2001/XMLSchema#date"
      Ash.Type.UtcDatetime -> "http://www.w3.org/2001/XMLSchema#dateTime"
      Ash.Type.UtcDatetimeUsec -> "http://www.w3.org/2001/XMLSchema#dateTime"
      _ -> nil
    end
  end

  defp shape_id(resource), do: resource |> Module.split() |> Enum.join("_")
end

defmodule AshR2ml.Validation do
  @moduledoc "Produces an evidence-bounded side-by-side migration receipt."

  alias AshR2ml.Resource.Info

  defstruct [
    :status,
    :standing,
    :r2rml_sha256,
    :shacl_sha256,
    :query_parity,
    resources: [],
    controls: %{},
    executed: [],
    verified: [],
    blocked: []
  ]

  def validate(resources) do
    resources = List.wrap(resources)

    with {:ok, r2rml} <- AshR2ml.R2RML.render(resources),
         {:ok, shacl} <- AshR2ml.SHACL.render(resources) do
      %__MODULE__{
        status: :PARTIAL_ALIVE,
        standing: :semantic_projection_only,
        r2rml_sha256: sha256(r2rml),
        shacl_sha256: sha256(shacl),
        query_parity: :UNKNOWN,
        resources: resources,
        controls: Map.new(resources, &{&1, Info.neo4j_control_present?(&1)}),
        executed: [:r2rml_render, :shacl_render],
        verified: [:mapping_closure, :deterministic_projection],
        blocked: [:sparql_sql_behavioral_parity, :cutover_authority]
      }
    else
      {:error, reason} ->
        %__MODULE__{
          status: :BLOCKED,
          standing: :no_cutover,
          query_parity: :UNKNOWN,
          resources: resources,
          blocked: [reason]
        }
    end
  end

  def cutover_ready?(%__MODULE__{query_parity: :VERIFIED, blocked: []}), do: true
  def cutover_ready?(_), do: false

  defp sha256(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
