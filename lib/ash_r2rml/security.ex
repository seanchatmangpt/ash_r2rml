# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Security do
  @moduledoc """
  Structural security transforms for semantic publication surfaces.

  Two independently observed authority gaps are closed here instead of being left to callers:

  * Ash field policies are enforceable on Ash-mediated reads but not by an external engine that
    reads the database directly. `sanitize_mapping/2` therefore removes field-policy-protected predicate maps from
    AshPostgres-backed mappings before R2RML rendering.
  * Ash extensions may replace an admitted attribute with a calculation under the same public
    name. `ash_cloak` does exactly this: the plaintext field becomes a decryption calculation
    while ciphertext lives in `encrypted_<name>`, and `decrypt_by_default` can load that
    calculation during an ordinary `Ash.read!/2`. `sanitize_in_memory_mapping/2` therefore
    removes any predicate map whose `attribute` no longer resolves to a real Ash attribute at
    execution time before `AshR2RML.OBDA.InMemory` can materialize the row.

  The second rule is intentionally extension-agnostic. A mapping property is admitted as an
  Ash *attribute* projection; a calculation, aggregate, or extension-manufactured derived
  field does not gain RDF-publication authority merely because it occupies the same struct
  key after a read. The removal is recorded in
  `mapping.metadata[:in_memory_non_attribute_excluded_attributes]` for auditability.
  """

  alias AshR2RML.Mapping.Resource

  @doc """
  Returns `mapping` unchanged unless `ash_resource` is `AshPostgres.DataLayer`-backed with
  R2RML-mapped attributes that also carry an explicit `field_policy`. Such attributes are
  removed and recorded in `mapping.metadata[:field_policy_excluded_attributes]` because
  a direct database reader has no Ash actor with which to enforce the policy.
  """
  @spec sanitize_mapping(module(), Resource.t()) :: Resource.t()
  def sanitize_mapping(ash_resource, %Resource{} = mapping) when is_atom(ash_resource) do
    if AshR2RML.DataLayer.backend(ash_resource) == :postgres do
      ash_resource
      |> unenforceable_attributes(mapping)
      |> then(&remove_attributes(mapping, &1, :field_policy_excluded_attributes))
    else
      mapping
    end
  end

  @doc """
  Fail-closed admission transform for `AshR2RML.OBDA.InMemory`.

  Every scalar predicate map whose declared `attribute` is no longer a real Ash attribute on
  the compiled resource is removed before graph construction. This closes the demonstrated
  `ash_cloak` `decrypt_by_default` plaintext leak without depending on `ash_cloak` at runtime
  or guessing extension-specific names. The same law applies to any future extension that
  replaces an attribute with a calculation or other derived field.
  """
  @spec sanitize_in_memory_mapping(module(), Resource.t()) :: Resource.t()
  def sanitize_in_memory_mapping(ash_resource, %Resource{} = mapping) when is_atom(ash_resource) do
    ash_resource
    |> non_attribute_mapped_fields(mapping)
    |> then(&remove_attributes(mapping, &1, :in_memory_non_attribute_excluded_attributes))
    |> sanitize_subject_map(ash_resource)
    |> sanitize_reference_object_maps(ash_resource)
  end

  # Subject map columns/template fields that are not real attributes are replaced by a
  # constant-free blank-node subject; the offending names are recorded in metadata.
  defp sanitize_subject_map(%Resource{subject_map: subject_map} = mapping, ash_resource) do
    bad =
      subject_map
      |> subject_fields()
      |> Enum.reject(&attribute_column?(ash_resource, &1))

    case bad do
      [] ->
        mapping

      _ ->
        stripped = %{subject_map | strategy: :blank_node, value: "excluded", term_type: :blank_node}

        %{
          mapping
          | subject_map: stripped,
            metadata: Map.put(mapping.metadata, :in_memory_non_attribute_subject_fields, Enum.uniq(bad))
        }
    end
  end

  # Reference object maps whose child join column is not a real attribute are removed.
  defp sanitize_reference_object_maps(%Resource{reference_object_maps: refs} = mapping, ash_resource) do
    {kept, dropped} =
      Enum.split_with(refs, fn ref ->
        Enum.all?(ref.joins || [], &attribute_column?(ash_resource, &1.child))
      end)

    case dropped do
      [] ->
        mapping

      _ ->
        %{
          mapping
          | reference_object_maps: kept,
            metadata:
              Map.put(
                mapping.metadata,
                :in_memory_non_attribute_join_relationships,
                dropped |> Enum.map(& &1.relationship) |> Enum.uniq()
              )
        }
    end
  end

  defp subject_fields(%{strategy: :column, value: value}), do: [value]

  defp subject_fields(%{strategy: :template, value: value}) when is_binary(value) do
    ~r/\{([^}]+)\}/ |> Regex.scan(value, capture: :all_but_first) |> List.flatten()
  end

  defp subject_fields(_), do: []

  # Fail closed: any resolution error means the column is not admitted.
  defp attribute_column?(ash_resource, column) do
    name = to_string(column)

    ash_resource
    |> Ash.Resource.Info.attributes()
    |> Enum.any?(fn attr ->
      to_string(attr.name) == name or (not is_nil(attr.source) and to_string(attr.source) == name)
    end)
  rescue
    _ -> false
  end

  @doc """
  Returns mapped scalar field names that do not resolve to real Ash attributes on the compiled
  resource. A returned name may still resolve to a calculation or aggregate; that is exactly
  why it is not implicitly admitted for RDF publication.
  """
  @spec non_attribute_mapped_fields(module(), Resource.t()) :: [atom()]
  def non_attribute_mapped_fields(ash_resource, %Resource{predicate_object_maps: predicate_object_maps}) do
    predicate_object_maps
    |> Enum.map(& &1.attribute)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(fn attribute ->
      is_nil(Ash.Resource.Info.attribute(ash_resource, attribute))
    end)
  rescue
    _ ->
      predicate_object_maps
      |> Enum.map(& &1.attribute)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
  end

  @doc """
  Pure transform using the field-policy audit key. Kept for compatibility with the v26.8.25
  security API.
  """
  @spec remove_attributes(Resource.t(), [atom()]) :: Resource.t()
  def remove_attributes(%Resource{} = mapping, attributes) when is_list(attributes) do
    remove_attributes(mapping, attributes, :field_policy_excluded_attributes)
  end

  @doc """
  Pure transform: removes `attributes`' predicate maps and records the exclusion under the
  supplied metadata key. An empty list is a byte-for-byte semantic no-op.
  """
  @spec remove_attributes(Resource.t(), [atom()], atom()) :: Resource.t()
  def remove_attributes(%Resource{} = mapping, [], _metadata_key), do: mapping

  def remove_attributes(%Resource{predicate_object_maps: predicate_object_maps} = mapping, attributes, metadata_key)
      when is_list(attributes) and is_atom(metadata_key) do
    attributes = Enum.uniq(attributes)
    kept = Enum.reject(predicate_object_maps, &(&1.attribute in attributes))

    %{
      mapping
      | predicate_object_maps: kept,
        metadata: Map.put(mapping.metadata, metadata_key, attributes)
    }
  end

  @doc """
  Returns the R2RML-mapped attributes on `ash_resource` that also carry an explicit Ash
  `field_policy`, independent of data layer. `sanitize_mapping/2` gates the actual exclusion
  on `AshPostgres.DataLayer`.
  """
  @spec unenforceable_attributes(module(), Resource.t()) :: [atom()]
  def unenforceable_attributes(ash_resource, %Resource{predicate_object_maps: predicate_object_maps}) do
    predicate_object_maps
    |> Enum.map(& &1.attribute)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(&field_policy_protected?(ash_resource, &1))
  end

  defp field_policy_protected?(ash_resource, attribute) do
    Code.ensure_loaded?(Ash.Policy.Info) and
      match?([_ | _], Ash.Policy.Info.field_policies_for_field(ash_resource, attribute))
  rescue
    _ -> true
  end
end
