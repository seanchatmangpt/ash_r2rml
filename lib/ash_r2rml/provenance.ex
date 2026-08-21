# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Provenance do
  @moduledoc """
  Pure semantic plumbing for explicitly admitted W3C PROV-O projections.

  Provenance is never invented by convention. `project/2` accepts only provenance
  choices supplied by the caller and verifies that field references, datatypes,
  and template references resolve against the mapped Ash resource before adding
  them.
  """

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Mapping.{Datatype, ObjectMap, PredicateObjectMap, Resource}
  alias AshR2RML.Refusal

  @prov "http://www.w3.org/ns/prov#"
  @xsd "http://www.w3.org/2001/XMLSchema#"
  @xsd_datetime @xsd <> "dateTime"

  @doc "Project explicitly configured provenance mappings onto one normalized resource."
  @spec project(Resource.t(), map() | keyword() | nil) :: {:ok, Resource.t()} | {:error, Refusal.t()}
  def project(%Resource{} = resource, nil), do: {:ok, resource}

  def project(%Resource{} = resource, config) when is_map(config) or is_list(config) do
    generated_at = get(config, :generated_at)
    derived_from = get(config, :derived_from)

    with {:ok, generated_at_datatype} <- validate_generated_at(resource, generated_at),
         :ok <- validate_template(resource, derived_from) do
      resource =
        if generated_at do
          attach_generated_at_time(resource, generated_at, generated_at_datatype)
        else
          resource
        end

      resource = if derived_from, do: attach_was_derived_from(resource, derived_from), else: resource
      {:ok, resource}
    end
  end

  def project(%Resource{} = resource, other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       resource.ash_resource,
       "provenance configuration must be a map, keyword list, or nil",
       %{provenance: inspect(other)}
     )}
  end

  @doc """
  Attach `prov:generatedAtTime` using the standard XSD dateTime contract.

  Prefer `project/2` when accepting caller input because it validates the source
  field and datatype first. This lower-level function is retained for callers
  that already own that admission proof.
  """
  @spec attach_generated_at_time(Resource.t(), String.t() | atom()) :: Resource.t()
  def attach_generated_at_time(%Resource{} = resource, column_or_attr) do
    attach_generated_at_time(
      resource,
      column_or_attr,
      %Datatype{ash_type: :utc_datetime, rdf_datatype: @xsd_datetime, storage_type: :utc_datetime}
    )
  end

  @doc "Attach prov:wasDerivedFrom to an explicitly admitted parent IRI template."
  @spec attach_was_derived_from(Resource.t(), String.t()) :: Resource.t()
  def attach_was_derived_from(%Resource{} = resource, parent_template) do
    pom = %PredicateObjectMap{
      attribute: nil,
      predicate_iri: @prov <> "wasDerivedFrom",
      object_map: %ObjectMap{
        strategy: :template,
        value: parent_template,
        term_type: :iri
      }
    }

    put_predicate(resource, pom)
  end

  defp attach_generated_at_time(resource, column_or_attr, %Datatype{} = datatype) do
    column_str = to_string(column_or_attr)

    pom = %PredicateObjectMap{
      attribute: if(is_atom(column_or_attr), do: column_or_attr, else: nil),
      predicate_iri: @prov <> "generatedAtTime",
      object_map: %ObjectMap{
        strategy: :column,
        value: column_str,
        datatype: datatype,
        term_type: :literal
      }
    }

    put_predicate(resource, pom)
  end

  defp validate_generated_at(_resource, nil), do: {:ok, nil}

  defp validate_generated_at(resource, field) when is_atom(field) or is_binary(field) do
    field_name = to_string(field)

    cond do
      field_name not in available_fields(resource) ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           {resource.ash_resource, field},
           "PROV-O generatedAtTime source is not an admitted Ash/mapping field",
           %{available_fields: available_fields(resource)}
         )}

      true ->
        case source_datatype(resource, field_name) do
          {:ok, %Datatype{rdf_datatype: @xsd_datetime} = datatype} ->
            {:ok, datatype}

          {:ok, %Datatype{} = datatype} ->
            {:error,
             Refusal.new(
               :REFUSED_UNMAPPED_DATATYPE,
               {resource.ash_resource, field},
               "PROV-O generatedAtTime requires a field whose admitted RDF datatype is xsd:dateTime",
               %{rdf_datatype: datatype.rdf_datatype, ash_type: datatype.ash_type}
             )}

          {:error, %Refusal{} = refusal} ->
            {:error, refusal}

          :unknown ->
            {:error,
             Refusal.new(
               :REFUSED_UNMAPPED_DATATYPE,
               {resource.ash_resource, field},
               "PROV-O generatedAtTime source exists but its datatype cannot be proven as xsd:dateTime"
             )}
        end
    end
  end

  defp validate_generated_at(resource, field) do
    {:error,
     Refusal.new(
       :REFUSED_UNKNOWN_ATTRIBUTE,
       {resource.ash_resource, field},
       "PROV-O generatedAtTime source must name an admitted field"
     )}
  end

  defp validate_template(_resource, nil), do: :ok

  defp validate_template(resource, template) when is_binary(template) do
    referenced = AshR2RML.Mapping.template_fields(template)
    missing = referenced -- available_fields(resource)

    cond do
      referenced == [] ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           resource.ash_resource,
           "PROV-O wasDerivedFrom template must reference at least one admitted identity field",
           %{template: template}
         )}

      missing != [] ->
        {:error,
         Refusal.new(
           :REFUSED_UNKNOWN_ATTRIBUTE,
           resource.ash_resource,
           "PROV-O wasDerivedFrom template references fields absent from the admitted resource",
           %{template: template, missing_fields: missing, available_fields: available_fields(resource)}
         )}

      true ->
        :ok
    end
  end

  defp validate_template(resource, template) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       resource.ash_resource,
       "PROV-O wasDerivedFrom must be an explicit IRI template",
       %{template: inspect(template)}
     )}
  end

  defp source_datatype(%Resource{} = resource, field_name) do
    case Enum.find(resource.predicate_object_maps, &pom_matches_field?(&1, field_name)) do
      %PredicateObjectMap{object_map: %ObjectMap{datatype: %Datatype{} = datatype}} ->
        {:ok, datatype}

      _ ->
        source_datatype_from_ash(resource.ash_resource, field_name)
    end
  end

  defp source_datatype_from_ash(module, field_name) when is_atom(module) do
    if Code.ensure_loaded?(module) and Ash.Resource.Info.resource?(module) do
      case Enum.find(Ash.Resource.Info.attributes(module), &(to_string(&1.name) == field_name)) do
        nil -> :unknown
        attribute -> Registry.resolve(attribute.type)
      end
    else
      :unknown
    end
  rescue
    _ -> :unknown
  end

  defp source_datatype_from_ash(_, _), do: :unknown

  defp pom_matches_field?(%PredicateObjectMap{} = pom, field_name) do
    to_string(pom.attribute || "") == field_name or
      match?(%ObjectMap{strategy: :column, value: ^field_name}, pom.object_map)
  end

  defp available_fields(%Resource{} = resource) do
    from_mapping =
      resource.predicate_object_maps
      |> List.wrap()
      |> Enum.flat_map(fn pom ->
        object_value = if match?(%ObjectMap{}, pom.object_map), do: pom.object_map.value, else: nil
        [pom.attribute, object_value]
      end)

    from_metadata =
      case resource.metadata do
        %{attribute_columns: columns} when is_map(columns) -> Map.keys(columns) ++ Map.values(columns)
        _ -> []
      end

    from_ash = ash_fields(resource.ash_resource)

    (from_mapping ++ from_metadata ++ from_ash)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp ash_fields(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and Ash.Resource.Info.resource?(module) do
      module
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)
    else
      []
    end
  rescue
    _ -> []
  end

  defp ash_fields(_), do: []

  defp put_predicate(%Resource{predicate_object_maps: poms} = resource, %PredicateObjectMap{} = pom) do
    retained = Enum.reject(List.wrap(poms), &(&1.predicate_iri == pom.predicate_iri))
    %{resource | predicate_object_maps: retained ++ [pom]}
  end

  defp get(config, key) when is_list(config), do: Keyword.get(config, key)
  defp get(config, key) when is_map(config), do: Map.get(config, key, Map.get(config, Atom.to_string(key)))
end
