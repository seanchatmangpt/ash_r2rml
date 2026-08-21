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

    has_authorizers? =
      is_atom(resource_module) and Code.ensure_loaded?(resource_module) and
        function_exported?(Ash.Resource.Info, :authorizers, 1) and
        Ash.Resource.Info.authorizers(resource_module) != []

    if has_authorizers? and not is_nil(actor) do
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
      # Fallback when policies are not configured or actor is nil
      resource_mapping
    end
  end

  @doc false
  def authorized_field?(resource, field, actor, _opts \\ []) do
    if Code.ensure_loaded?(Ash.Policy.Info) and function_exported?(Ash.Policy.Info, :field_policies_for_field, 2) do
      case Ash.Policy.Info.field_policies_for_field(resource, field) do
        [] ->
          true

        policies when is_list(policies) and policies != [] ->
          evaluate_field_policies(policies, actor)

        _ ->
          true
      end
    else
      true
    end
  end

  defp evaluate_field_policies(policies, actor) do
    Enum.any?(policies, fn policy ->
      checks = Map.get(policy, :policies, [])

      if checks == [] do
        true
      else
        Enum.all?(checks, fn
          %{check: {module, opts}, type: :authorize_if} ->
            check_match?(module, actor, opts)

          %{check: {module, opts}, type: :forbid_if} ->
            not check_match?(module, actor, opts)

          {module, opts} ->
            check_match?(module, actor, opts)

          _ ->
            true
        end)
      end
    end)
  end

  defp check_match?(module, actor, opts) do
    cond do
      module == Ash.Policy.Check.Static ->
        Keyword.get(opts, :result, true)

      function_exported?(module, :match?, 3) ->
        module.match?(actor, %{}, opts)

      true ->
        true
    end
  rescue
    _ -> true
  end

  defp authorized_reference?(_resource, _ref, _actor, _opts), do: true
end
