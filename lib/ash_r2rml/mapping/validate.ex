# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate do
  @moduledoc """
  Fail-closed validation of the mapping IR, composed from rule-group modules.

  Called through `AshR2RML.Mapping.validate/1`; refusal codes and ordering are
  part of the public contract. Rule groups live in `AshR2RML.Mapping.Validate.*`:
  `Subject` (logical table, classes, subject map), `Properties`, `References`,
  `GraphMaps` and `BundleRules`.

      iex> AshR2RML.Mapping.Validate.absolute_iri?("http://schema.org/a")
      true
      iex> AshR2RML.Mapping.Validate.absolute_iri?("relative/path")
      false
  """

  alias AshR2RML.Mapping

  alias AshR2RML.Mapping.Validate.{
    BundleRules,
    GraphMaps,
    Properties,
    References,
    Shared,
    Subject
  }

  alias AshR2RML.Mapping.{Bundle, Resource}
  alias AshR2RML.Refusal

  @doc """
  Validates one resource mapping or a whole bundle.

  Returns `:ok` or `{:error, refusals}` with refusals in rule-group order.
  """
  @spec run(Resource.t() | Bundle.t()) :: :ok | {:error, [Refusal.t(), ...]}
  def run(%Resource{} = resource) do
    {missing_object, present} = Enum.split_with(resource.predicate_object_maps, &is_nil(&1.object_map))
    checked = %{resource | predicate_object_maps: present}

    refusals =
      Subject.logical_table(resource) ++
        Subject.classes(resource) ++
        Subject.subject(resource) ++
        Properties.check(checked) ++
        missing_object_map(resource, missing_object) ++
        Properties.duplicates(resource) ++
        References.check(resource) ++
        References.duplicates(resource) ++
        GraphMaps.resource(resource)

    to_result(refusals)
  end

  def run(%Bundle{} = bundle) do
    bundle = Mapping.normalize(bundle)
    by_resource = Map.new(bundle.resources, &{&1.ash_resource, &1})

    refusals =
      Enum.flat_map(bundle.resources, &bundled_resource(&1, by_resource)) ++
        BundleRules.duplicate_subject_contracts(bundle.resources) ++
        duplicate_resources(bundle.resources)

    to_result(refusals)
  end

  @doc false
  @spec absolute_iri?(term()) :: boolean()
  defdelegate absolute_iri?(value), to: Shared

  defp missing_object_map(resource, mappings) do
    Enum.map(mappings, fn mapping ->
      Refusal.new(
        :REFUSED_INVALID_TERM_MAP,
        {resource.ash_resource, mapping.attribute},
        "predicate-object map requires an object map",
        %{predicate_iri: mapping.predicate_iri}
      )
    end)
  end

  defp duplicate_resources(resources) do
    resources
    |> Enum.frequencies_by(& &1.ash_resource)
    |> Enum.filter(fn {_resource, count} -> count > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {ash_resource, count} ->
      Refusal.new(
        :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY,
        ash_resource,
        "bundle lists more than one mapping for the same ash_resource",
        %{ash_resource: ash_resource, entries: count}
      )
    end)
  end

  defp bundled_resource(resource, by_resource) do
    own =
      case run(resource) do
        :ok -> []
        {:error, values} -> values
      end

    own ++ BundleRules.reference_targets(resource, by_resource)
  end

  defp to_result([]), do: :ok
  defp to_result(refusals), do: {:error, refusals}
end
