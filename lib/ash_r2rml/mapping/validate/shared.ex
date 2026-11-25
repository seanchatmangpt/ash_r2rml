# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Mapping.Validate.Shared do
  @moduledoc """
  Helpers shared by the mapping validation rule groups.

      iex> AshR2RML.Mapping.Validate.Shared.absolute_iri?("http://schema.org/a")
      true
      iex> AshR2RML.Mapping.Validate.Shared.absolute_iri?("has space://x")
      false
      iex> AshR2RML.Mapping.Validate.Shared.non_empty_string?("")
      false
  """

  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{ObjectMap, Resource}
  alias AshR2RML.Refusal

  # IRIREF forbids: control chars, space, < > " { } | ^ ` \
  @iri_forbidden ~r/[\x00-\x20\x7f<>"{}|^`\\]/

  @doc "True when `value` is a binary IRI with a scheme and no IRIREF-forbidden characters."
  @spec absolute_iri?(term()) :: boolean()
  def absolute_iri?(value) when is_binary(value) do
    not Regex.match?(@iri_forbidden, value) and
      match?(%URI{scheme: scheme} when is_binary(scheme) and scheme != "", URI.parse(value))
  end

  def absolute_iri?(_), do: false

  @doc "True for a non-empty binary."
  @spec non_empty_string?(term()) :: boolean()
  def non_empty_string?(value), do: is_binary(value) and value != ""

  @doc "Appends a refusal when the rule step produced one (nil means the rule passed)."
  @spec maybe_add([Refusal.t()], Refusal.t() | nil) :: [Refusal.t()]
  def maybe_add(acc, nil), do: acc
  def maybe_add(acc, %Refusal{} = refusal), do: acc ++ [refusal]

  @doc "Keys occurring more than once, sorted."
  @spec duplicate_keys([term()], (term() -> term())) :: [term()]
  def duplicate_keys(items, key_fun) do
    items
    |> Enum.map(key_fun)
    |> Enum.frequencies()
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  @doc "Column names the resource mapping can supply to a template or column term map."
  @spec available_columns(Resource.t()) :: MapSet.t(String.t())
  def available_columns(resource) do
    metadata_columns = resource.metadata |> Map.get(:attribute_columns, %{}) |> Map.values()
    all_identity_cols = resource |> Mapping.identity_column_sets() |> List.flatten()

    # With declared columns, an identity column must itself be a declared column.
    identity_cols =
      if columns_declared?(resource),
        do: Enum.filter(all_identity_cols, &(&1 in metadata_columns)),
        else: all_identity_cols

    # Self-admission of :column object values applies only when the mapping
    # declares no columns; a declared column set is authoritative.
    property_columns =
      if columns_declared?(resource) do
        []
      else
        Enum.flat_map(resource.predicate_object_maps, fn mapping ->
          case mapping.object_map do
            %ObjectMap{strategy: :column, value: value} -> [value]
            _ -> []
          end
        end)
      end

    MapSet.new(metadata_columns ++ identity_cols ++ property_columns)
  end

  @doc "True when the mapping declares its columns via non-empty `metadata.attribute_columns`."
  @spec columns_declared?(Resource.t()) :: boolean()
  def columns_declared?(resource) do
    match?(%{attribute_columns: columns} when is_map(columns) and map_size(columns) > 0, resource.metadata)
  end

  @doc "One refusal naming every template field the resource mapping cannot supply."
  @spec template_refusals(Resource.t(), String.t(), atom(), term(), String.t()) :: [Refusal.t()]
  def template_refusals(resource, template, code, subject, detail) do
    available = available_columns(resource)

    case Enum.reject(Mapping.template_fields(template), &MapSet.member?(available, &1)) do
      [] -> []
      missing -> [Refusal.new(code, subject, detail, %{missing: missing, template: template})]
    end
  end
end
