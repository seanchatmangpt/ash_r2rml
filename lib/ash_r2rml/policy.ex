# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Policy do
  @moduledoc """
  Policy-aware semantic projection filter.

  Filters `AshR2RML.Mapping.Resource` and `AshR2RML.Mapping.Bundle` instances to omit
  predicateObjectMaps and referenceObjectMaps for attributes/relationships that the given actor
  is not authorized to read under Ash policies.
  """

  alias AshR2RML.Mapping.{Bundle, PredicateObjectMap, ReferenceObjectMap, Resource}

  @doc """
  Filters a Resource mapping or Bundle for the given actor context.
  """
  @spec filter_for_actor(Resource.t() | Bundle.t(), term(), keyword()) :: Resource.t() | Bundle.t()
  def filter_for_actor(%Bundle{resources: resources} = bundle, actor, opts) do
    filtered_resources = Enum.map(resources, &filter_for_actor(&1, actor, opts))
    %{bundle | resources: filtered_resources}
  end

  def filter_for_actor(%Resource{} = resource_mapping, actor, opts) do
    resource_module = Map.get(resource_mapping, :ash_resource) || Map.get(resource_mapping, :module)

    if Code.ensure_loaded?(Ash.Can) and is_atom(resource_module) and function_exported?(resource_module, :ash_can, 3) do
      allowed_attributes =
        Enum.filter(resource_mapping.predicate_object_maps, fn %PredicateObjectMap{attribute: attr} ->
          is_nil(attr) or authorized_field?(resource_module, attr, actor, opts)
        end)

      allowed_references =
        Enum.filter(resource_mapping.reference_object_maps, fn %ReferenceObjectMap{} = ref ->
          authorized_reference?(resource_module, ref, actor, opts)
        end)

      %{resource_mapping | predicate_object_maps: allowed_attributes, reference_object_maps: allowed_references}
    else
      # Fallback when policies are not configured or Ash.Can is not present
      resource_mapping
    end
  end

  defp authorized_field?(resource, field, actor, opts) do
    action = Keyword.get(opts, :action, :read)

    case Ash.Can.can(resource, action, actor, field: field) do
      {:ok, true} -> true
      {:ok, false} -> false
      _ -> true
    end
  rescue
    _ -> true
  end

  defp authorized_reference?(_resource, _ref, _actor, _opts), do: true
end
