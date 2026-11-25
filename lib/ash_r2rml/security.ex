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
  Returns `mapping` unchanged unless `ash_resource` is not `Ash.DataLayer.Ets`-backed (unknown
  layers fail closed) with
  R2RML-mapped attributes that also carry an explicit `field_policy`. Such attributes are
  removed and recorded in `mapping.metadata[:field_policy_excluded_attributes]` because
  a direct database reader has no Ash actor with which to enforce the policy.
  """
  @spec sanitize_mapping(module(), Resource.t()) :: Resource.t()
  def sanitize_mapping(ash_resource, %Resource{} = mapping) when is_atom(ash_resource) do
    # Only Ash-mediated in-memory (:ets) reads can enforce field policies; every other layer,
    # including :unknown (fail closed), is read directly by an external R2RML engine.
    mapping =
      if AshR2RML.DataLayer.backend(ash_resource) != :ets do
        ash_resource
        |> unenforceable_attributes(mapping)
        |> then(&remove_attributes(mapping, &1, :field_policy_excluded_attributes))
      else
        mapping
      end

    ash_resource
    |> sensitive_mapped_attributes(mapping)
    |> then(&remove_attributes(mapping, &1, :sensitive_excluded_attributes))
  end

  @doc """
  Refuses a mapping whose subject map, graph maps, object term maps or reference joins depend
  on a protected attribute (`sensitive?: true`, or field-policy-protected on a non-`:ets` layer).
  Predicate maps are handled by `sanitize_mapping/2`; this closes the remaining render paths.
  Mappings that touch no protected attribute return `:ok` unchanged.
  """
  @spec check_protected_dependencies(module(), Resource.t()) :: :ok | {:error, AshR2RML.Refusal.t()}
  def check_protected_dependencies(ash_resource, %Resource{} = mapping) when is_atom(ash_resource) do
    own =
      [{"subject map", subject_fields(mapping.subject_map)}] ++
        [{"graph map", Enum.flat_map(all_graph_maps(mapping), &graph_fields/1)}] ++
        [{"object term map", Enum.flat_map(mapping.predicate_object_maps, &object_fields(&1.object_map))}] ++
        [
          {"reference join child column",
           for(ref <- mapping.reference_object_maps, join <- ref.joins || [], do: join.child)}
        ]

    parent_checks =
      for ref <- mapping.reference_object_maps,
          is_atom(ref.parent_resource) and not is_nil(ref.parent_resource),
          join <- ref.joins || [] do
        {ref.parent_resource, "reference join parent column", join.parent}
      end

    own_hit =
      Enum.find_value(own, fn {where, fields} ->
        case Enum.find(fields, &protected_column?(ash_resource, &1)) do
          nil -> nil
          field -> {where, field}
        end
      end)

    hit =
      own_hit ||
        Enum.find_value(parent_checks, fn {parent, where, field} ->
          if protected_column?(parent, field), do: {where, field}
        end)

    case hit do
      nil ->
        :ok

      {where, field} ->
        {:error,
         AshR2RML.Refusal.new(
           :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
           mapping.ash_resource,
           "protected attribute #{inspect(to_string(field))} cannot be used in a #{where} of an external R2RML mapping",
           %{field: to_string(field), where: where}
         )}
    end
  end

  defp all_graph_maps(mapping) do
    mapping.graph_maps ++
      mapping.subject_map.graph_maps ++
      Enum.flat_map(mapping.predicate_object_maps, &(&1.graph_maps ++ &1.object_map.graph_maps)) ++
      Enum.flat_map(mapping.reference_object_maps, & &1.graph_maps)
  end

  defp graph_fields(%{strategy: :column, value: value}), do: [value]
  defp graph_fields(%{strategy: :template, value: value}) when is_binary(value), do: template_columns(value)
  defp graph_fields(_), do: []

  defp object_fields(%{strategy: :column, value: value}), do: [value]
  defp object_fields(%{strategy: :template, value: value}) when is_binary(value), do: template_columns(value)
  defp object_fields(_), do: []

  defp template_columns(template) do
    ~r/\{([^{}]+)\}/ |> Regex.scan(template, capture: :all_but_first) |> List.flatten()
  end

  # Unresolvable columns are not protected attributes; a raising lookup fails closed.
  defp protected_column?(resource, column) do
    name = to_string(column)

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.find(fn attr ->
      to_string(attr.name) == name or (not is_nil(attr.source) and to_string(attr.source) == name)
    end)
    |> case do
      nil ->
        false

      attr ->
        attr.sensitive? == true or
          (AshR2RML.DataLayer.backend(resource) != :ets and field_policy_protected?(resource, attr.name))
    end
  rescue
    _ -> true
  end

  @doc """
  Returns mapped attributes marked `sensitive?: true` on `ash_resource`. Fails closed: if
  attribute resolution raises, every mapped attribute is treated as sensitive.
  """
  @spec sensitive_mapped_attributes(module(), Resource.t()) :: [atom()]
  def sensitive_mapped_attributes(ash_resource, %Resource{predicate_object_maps: predicate_object_maps}) do
    attrs =
      predicate_object_maps
      |> Enum.map(& &1.attribute)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.filter(attrs, fn attribute ->
      try do
        match?(%{sensitive?: true}, Ash.Resource.Info.attribute(ash_resource, attribute))
      rescue
        _ -> true
      end
    end)
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

  @doc false
  @spec field_policy_protected?(module(), atom()) :: boolean()
  def field_policy_protected?(ash_resource, attribute) do
    Code.ensure_loaded?(Ash.Policy.Info) and
      match?([_ | _], Ash.Policy.Info.field_policies_for_field(ash_resource, attribute))
  rescue
    _ -> true
  end
end
