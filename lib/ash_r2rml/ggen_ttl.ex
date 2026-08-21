# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ggen.TTL do
  @moduledoc """
  Deterministic ggen TTL projection manufactured from canonical AshR2RML mappings.

  This reverses the old maintenance direction for cloud ggen. Ash resources and
  their admitted AshR2RML metadata are the maintained source. The ontology,
  operational SHACL shapes, and R2RML mapping are generated projections of the
  same canonical `AshR2RML.Mapping.Bundle`.

  No filesystem actuation occurs here. Callers receive a path/content graph that
  ggen may materialize under its own authority and receipt boundary.
  """

  alias AshR2RML.Mapping.{Bundle, PredicateObjectMap, ReferenceObjectMap, Resource}

  @prefixes """
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
  @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

  """

  @doc "Compile Ash resources and emit the complete TTL input graph expected by ggen."
  @spec emit(module() | [module()] | Bundle.t()) :: {:ok, map()} | {:error, term()}
  def emit(resources_or_bundle) do
    with {:ok, bundle} <- bundle(resources_or_bundle),
         {:ok, ontology} <- ontology(bundle),
         {:ok, shacl} <- AshR2RML.SHACL.render(bundle),
         {:ok, r2rml} <- AshR2RML.R2RML.render(bundle) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         source: :ash,
         files: %{
           "ontology.ttl" => ontology,
           "shapes/operational-profile.ttl" => shacl,
           "r2rml/mapping.ttl" => r2rml
         },
         sha256: %{
           ontology: sha256(ontology),
           shacl: sha256(shacl),
           r2rml: sha256(r2rml)
         }
       }}
    end
  end

  @doc "Render the RDF vocabulary projection represented by an AshR2RML mapping bundle."
  @spec ontology(Bundle.t()) :: {:ok, String.t()}
  def ontology(%Bundle{resources: resources}) do
    resources = Enum.sort_by(resources, &resource_key/1)

    class_statements =
      resources
      |> Enum.flat_map(fn %Resource{class_iris: classes} -> classes end)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&"<#{&1}> a rdfs:Class .")

    scalar_statements =
      resources
      |> Enum.flat_map(&scalar_statements/1)
      |> Enum.uniq()
      |> Enum.sort()

    relationship_statements =
      resources
      |> Enum.flat_map(&relationship_statements(&1, resources))
      |> Enum.uniq()
      |> Enum.sort()

    body = Enum.join(class_statements ++ scalar_statements ++ relationship_statements, "\n")
    {:ok, @prefixes <> body <> if(body == "", do: "", else: "\n")}
  end

  defp bundle(%Bundle{} = bundle), do: {:ok, bundle}

  defp bundle(resources) when is_atom(resources) or is_list(resources) do
    AshR2RML.Compiler.compile(resources)
  end

  defp scalar_statements(%Resource{} = resource) do
    for %PredicateObjectMap{} = mapping <- resource.predicate_object_maps,
        domain <- resource.class_iris do
      range = datatype_range(mapping)
      "<#{mapping.predicate_iri}> a rdf:Property ; rdfs:domain <#{domain}>#{range} ."
    end
  end

  defp relationship_statements(%Resource{} = resource, resources) do
    for %ReferenceObjectMap{} = mapping <- resource.reference_object_maps,
        domain <- resource.class_iris,
        range <- target_classes(mapping.parent_resource, resources) do
      "<#{mapping.predicate_iri}> a rdf:Property ; rdfs:domain <#{domain}> ; rdfs:range <#{range}> ."
    end
  end

  defp target_classes(parent_resource, resources) do
    resources
    |> Enum.find(fn resource -> resource.ash_resource == parent_resource end)
    |> case do
      nil -> []
      %Resource{class_iris: classes} -> classes
    end
  end

  defp datatype_range(%PredicateObjectMap{object_map: %{datatype: %{rdf_datatype: datatype}}})
       when is_binary(datatype),
       do: " ; rdfs:range <#{datatype}>"

  defp datatype_range(_), do: ""

  defp resource_key(%Resource{ash_resource: resource}) when is_atom(resource), do: inspect(resource)
  defp resource_key(%Resource{ash_resource: resource}), do: to_string(resource)

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
