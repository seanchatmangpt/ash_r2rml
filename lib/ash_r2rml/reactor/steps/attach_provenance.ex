# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.AttachProvenance do
  @moduledoc """
  Reactor step for explicitly admitted W3C PROV-O projection.

  The step is a no-op unless the caller supplies provenance configuration. It
  never invents an `updated_at` field or an application-specific source IRI.
  Configuration may be supplied directly as `:provenance` or nested under the
  pipeline `:metadata` map.

  A flat configuration applies to all resources. Callers that need heterogeneous
  provenance may use `%{default: ..., resources: %{ResourceModule => ...}}`;
  resource-specific values override the default without changing the canonical
  mapping ownership boundary.
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{bundle: bundle} = arguments, _context, _options) do
    provenance =
      Map.get(arguments, :provenance) ||
        arguments
        |> Map.get(:metadata, %{})
        |> provenance_from_metadata()

    Enum.reduce_while(bundle.resources || [], {:ok, []}, fn resource, {:ok, acc} ->
      config = resource_config(resource, provenance)

      case AshR2RML.Mapping.Provenance.apply(resource, config) do
        {:ok, projected} -> {:cont, {:ok, [projected | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, resources} -> {:ok, %{bundle | resources: Enum.reverse(resources)}}
      {:error, _} = error -> error
    end
  end

  defp provenance_from_metadata(metadata) when is_map(metadata) do
    Map.get(metadata, :provenance, Map.get(metadata, "provenance"))
  end

  defp provenance_from_metadata(_), do: nil

  defp resource_config(_resource, nil), do: nil

  defp resource_config(resource, config) when is_map(config) do
    default = Map.get(config, :default, Map.get(config, "default"))
    resources = Map.get(config, :resources, Map.get(config, "resources"))

    if is_map(default) or is_map(resources) do
      default = if is_map(default), do: default, else: %{}
      override = lookup_override(resources || %{}, resource)
      Map.merge(default, override)
    else
      config
    end
  end

  defp resource_config(_resource, config), do: config

  defp lookup_override(resources, resource) do
    candidates =
      [
        resource.ash_resource,
        to_string(resource.ash_resource)
        | List.wrap(resource.class_iris)
      ]

    Enum.find_value(candidates, %{}, fn key ->
      case Map.fetch(resources, key) do
        {:ok, value} when is_map(value) -> value
        _ -> nil
      end
    end)
  end
end
