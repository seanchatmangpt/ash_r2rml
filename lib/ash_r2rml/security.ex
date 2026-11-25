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
    # Plain-column cloaked projections are dropped here; every other cloaked dependency is
    # refused by check_encrypted_projection/2.
    mapping = remove_cloaked_poms(ash_resource, mapping)

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
    with :ok <- check_encrypted_projection(ash_resource, mapping) do
      check_sensitive_dependencies(ash_resource, mapping)
    end
  end

  @doc """
  Names of attributes encrypted by AshCloak on `ash_resource`, detected by Spark introspection
  of the `cloak` DSL section (`attributes`), with no compile-time or runtime dependency on
  `ash_cloak`. Returns `[]` for resources without the extension; `cloaked_column?/2` fails
  closed (treats every column as cloaked) when introspection itself errors; this function
  raises `ArgumentError` in that case rather than reporting an empty (permissive) list.
  """
  @spec cloaked_attributes(module()) :: [atom()]
  def cloaked_attributes(ash_resource) when is_atom(ash_resource) do
    case cloaked_attributes_result(ash_resource) do
      {:ok, names} ->
        names

      :error ->
        raise ArgumentError,
              "cloak introspection failed for #{inspect(ash_resource)}; refusing to assume no cloaked attributes"
    end
  end

  defp cloaked_attributes_result(ash_resource) do
    case Spark.Dsl.Extension.get_opt(ash_resource, [:cloak], :attributes, []) do
      names when is_list(names) -> {:ok, Enum.filter(names, &is_atom/1)}
      _ -> :error
    end
  rescue
    _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> :error
  end

  # Column names (attribute names and `source` renames) that hold plaintext or ciphertext.
  defp cloaked_names(ash_resource, attrs) do
    Enum.flat_map(attrs, fn attr ->
      encrypted = String.to_atom("encrypted_" <> to_string(attr))

      [attr, encrypted]
      |> Enum.flat_map(fn name ->
        case Ash.Resource.Info.attribute(ash_resource, name) do
          %{source: source} when not is_nil(source) -> [name, source]
          _ -> [name]
        end
      end)
      |> Enum.map(&to_string/1)
    end)
  end

  @doc """
  True when `column` names a cloaked attribute of `ash_resource`, its `encrypted_<name>`
  ciphertext companion, or the `source` rename of either. Fails closed (true) when cloak
  introspection errors.
  """
  @spec cloaked_column?(module(), String.t() | atom()) :: boolean()
  def cloaked_column?(ash_resource, column) do
    case cloaked_attributes_result(ash_resource) do
      {:ok, attrs} -> to_string(column) in cloaked_names(ash_resource, attrs)
      :error -> true
    end
  rescue
    _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> true
  end

  @doc """
  True for an opaque enclave pointer term map: an IRI constant object map whose value is
  `urn:sha256:<64 lowercase hex>`. Templates are never pointers.
  """
  @spec enclave_pointer?(module(), struct()) :: boolean()
  def enclave_pointer?(_ash_resource, %{strategy: :constant, term_type: :iri, value: value}) when is_binary(value) do
    Regex.match?(~r/\Aurn:sha256:[0-9a-f]{64}\z/, value)
  end

  def enclave_pointer?(_ash_resource, _object_map), do: false

  # Predicate maps that project a cloaked column as a plain column are dropped (not refused).
  defp cloak_plain_column?(ash_resource, pom) do
    not enclave_pointer?(ash_resource, pom.object_map) and
      pom.object_map.strategy == :column and
      (cloaked_column?(ash_resource, pom.object_map.value) or
         (not is_nil(pom.attribute) and cloaked_column?(ash_resource, pom.attribute)))
  end

  defp remove_cloaked_poms(ash_resource, %Resource{predicate_object_maps: poms} = mapping) do
    {dropped, kept} = Enum.split_with(poms, &cloak_plain_column?(ash_resource, &1))

    case dropped do
      [] ->
        mapping

      _ ->
        names = dropped |> Enum.map(&(&1.attribute || &1.object_map.value)) |> Enum.uniq()
        %{mapping | predicate_object_maps: kept, metadata: Map.put(mapping.metadata, :cloak_excluded_attributes, names)}
    end
  end

  @doc """
  Refuses plaintext projection of AshCloak-encrypted attributes. Predicate-object maps over a
  cloaked attribute are admitted only as an opaque `urn:sha256:` enclave pointer; subject maps,
  graph maps, object term maps and reference joins (child or parent) that touch a cloaked
  attribute or its ciphertext column are always refused with
  `:REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION`.
  """
  @spec check_encrypted_projection(module(), Resource.t()) :: :ok | {:error, AshR2RML.Refusal.t()}
  def check_encrypted_projection(ash_resource, %Resource{} = mapping) when is_atom(ash_resource) do
    properties =
      for pom <- mapping.predicate_object_maps,
          not enclave_pointer?(ash_resource, pom.object_map),
          field <- [pom.attribute | object_fields(pom.object_map)],
          not is_nil(field) do
        {"property", field}
      end

    others =
      Enum.map(subject_fields(mapping.subject_map), &{"subject", &1}) ++
        Enum.map(Enum.flat_map(all_graph_maps(mapping), &graph_fields/1), &{"graph", &1}) ++
        Enum.map(Enum.flat_map(mapping.reference_object_maps, &child_columns/1), &{"join", &1})

    own = Enum.find(properties ++ others, fn {_, f} -> cloaked_column?(ash_resource, f) end)

    parent =
      for ref <- mapping.reference_object_maps,
          is_atom(ref.parent_resource) and not is_nil(ref.parent_resource),
          join <- ref.joins || [],
          cloaked_column?(ref.parent_resource, join.parent) do
        {"join", join.parent}
      end

    case own || List.first(parent) do
      nil ->
        :ok

      {where, field} ->
        {:error,
         AshR2RML.Refusal.new(
           :REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION,
           mapping.ash_resource,
           "encrypted attribute #{inspect(to_string(field))} cannot be projected in plaintext as a #{where}; " <>
             "map it as an opaque urn:sha256: enclave pointer",
           %{field: to_string(field), where: where}
         )}
    end
  end

  defp child_columns(ref), do: for(join <- ref.joins || [], do: join.child)

  defp check_sensitive_dependencies(ash_resource, mapping) do
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

  @doc false
  def all_graph_maps(mapping) do
    mapping.graph_maps ++
      mapping.subject_map.graph_maps ++
      Enum.flat_map(mapping.predicate_object_maps, &(&1.graph_maps ++ &1.object_map.graph_maps)) ++
      Enum.flat_map(mapping.reference_object_maps, & &1.graph_maps)
  end

  defp graph_fields(term_map), do: term_map_fields(term_map)

  defp object_fields(term_map), do: term_map_fields(term_map)

  # Columns read by a graph or object term map: the column itself or its template placeholders.
  defp term_map_fields(%{strategy: :column, value: value}), do: [value]

  defp term_map_fields(%{strategy: :template, value: value}) when is_binary(value),
    do: template_columns(value)

  defp term_map_fields(_), do: []

  # The single placeholder scanner for subject, graph and object templates.
  defp template_columns(template) do
    ~r/\{([^{}]+)\}/ |> Regex.scan(template, capture: :all_but_first) |> List.flatten()
  end

  # Resolves a column or placeholder name to attributes by attribute name or `source` rename.
  defp resolve_attributes(resource, column) do
    name = to_string(column)

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(fn attr ->
      to_string(attr.name) == name or (not is_nil(attr.source) and to_string(attr.source) == name)
    end)
  end

  # Unresolvable columns are not protected attributes; a raising lookup fails closed.
  defp protected_column?(resource, column) do
    resource
    |> resolve_attributes(column)
    |> Enum.any?(fn attr ->
      attr.sensitive? == true or
        (AshR2RML.DataLayer.backend(resource) != :ets and field_policy_protected?(resource, attr.name))
    end)
  rescue
    _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> true
  end

  @doc """
  Returns mapped attributes marked `sensitive?: true` on `ash_resource`. Fails closed: if
  attribute resolution raises, every mapped attribute is treated as sensitive.
  """
  @spec sensitive_mapped_attributes(module(), Resource.t()) :: [atom()]
  def sensitive_mapped_attributes(ash_resource, %Resource{predicate_object_maps: predicate_object_maps}) do
    predicate_object_maps
    |> mapped_attributes()
    |> Enum.filter(fn attribute ->
      try do
        match?(%{sensitive?: true}, Ash.Resource.Info.attribute(ash_resource, attribute))
      rescue
        _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> true
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
    # Protected-attribute refusal is typed and honors `allow_sensitive` in
    # `AshR2RML.OBDA.InMemory` (check_spec_sensitive); this transform only rejects
    # non-attribute subject fields, so it must not pre-empt that decision.
    case admit_in_memory_mapping(ash_resource, mapping, allow_sensitive: true) do
      {:ok, admitted} ->
        admitted

      {:error, %AshR2RML.Refusal{code: code, detail: detail}} ->
        raise ArgumentError, "#{code}: #{detail}"
    end
  end

  @doc """
  Typed admission for `AshR2RML.OBDA.InMemory`: refuses (instead of rewriting) a subject map
  whose placeholder or column is not a real, non-cloaked Ash attribute, and a subject map or
  graph map that reads a protected attribute (`sensitive?: true`, resolved by attribute name
  or `source`). Otherwise returns the mapping with non-attribute predicate maps, graph maps
  and reference joins stripped.
  """
  @spec admit_in_memory_mapping(module(), Resource.t(), keyword()) ::
          {:ok, Resource.t()} | {:error, AshR2RML.Refusal.t()}
  def admit_in_memory_mapping(ash_resource, %Resource{} = mapping, opts \\ []) when is_atom(ash_resource) do
    allow_sensitive? = Keyword.get(opts, :allow_sensitive, false) == true

    with :ok <- check_in_memory_subject(ash_resource, mapping, allow_sensitive?),
         :ok <- check_in_memory_graph_sensitivity(ash_resource, mapping, allow_sensitive?) do
      {:ok,
       ash_resource
       |> non_attribute_mapped_fields(mapping)
       |> then(&remove_attributes(mapping, &1, :in_memory_non_attribute_excluded_attributes))
       |> sanitize_graph_maps(ash_resource)
       |> sanitize_reference_object_maps(ash_resource)}
    end
  end

  defp check_in_memory_graph_sensitivity(_ash_resource, _mapping, true), do: :ok

  defp check_in_memory_graph_sensitivity(ash_resource, mapping, false) do
    mapping
    |> all_graph_maps()
    |> Enum.flat_map(&graph_fields/1)
    |> Enum.find(&protected_column?(ash_resource, &1))
    |> case do
      nil -> :ok
      field -> refuse_field(mapping, field, "graph map")
    end
  end

  defp check_in_memory_subject(ash_resource, mapping, allow_sensitive?) do
    fields = subject_fields(mapping.subject_map)

    case Enum.find(
           fields,
           &(not attribute_column?(ash_resource, &1) or (not allow_sensitive? and protected_column?(ash_resource, &1)))
         ) do
      nil -> :ok
      field -> refuse_field(mapping, field, "subject map")
    end
  end

  defp refuse_field(mapping, field, where) do
    {:error,
     AshR2RML.Refusal.new(
       :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
       mapping.ash_resource,
       "field #{inspect(to_string(field))} is not an admitted public attribute and cannot be used in the #{where} of an in-memory mapping",
       %{field: to_string(field), where: where}
     )}
  end

  # Graph maps reading a non-attribute or cloaked column are removed at every level.
  defp sanitize_graph_maps(%Resource{} = mapping, ash_resource) do
    ok? = fn gm -> gm |> graph_fields() |> Enum.all?(&attribute_column?(ash_resource, &1)) end
    keep = fn maps -> Enum.filter(maps, ok?) end
    total = length(all_graph_maps(mapping))

    stripped = %{
      mapping
      | graph_maps: keep.(mapping.graph_maps),
        subject_map: %{mapping.subject_map | graph_maps: keep.(mapping.subject_map.graph_maps)},
        predicate_object_maps:
          Enum.map(mapping.predicate_object_maps, fn pom ->
            %{
              pom
              | graph_maps: keep.(pom.graph_maps),
                object_map: %{pom.object_map | graph_maps: keep.(pom.object_map.graph_maps)}
            }
          end),
        reference_object_maps: Enum.map(mapping.reference_object_maps, &%{&1 | graph_maps: keep.(&1.graph_maps)})
    }

    case total - length(all_graph_maps(stripped)) do
      0 -> mapping
      n -> %{stripped | metadata: Map.put(stripped.metadata, :in_memory_graph_maps_excluded, n)}
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

  defp subject_fields(%{strategy: strategy, value: value})
       when strategy in [:template, :blank_node] and is_binary(value),
       do: template_columns(value)

  defp subject_fields(_), do: []

  # Fail closed: any resolution error means the column is not admitted.
  defp attribute_column?(ash_resource, column) do
    not cloaked_column?(ash_resource, column) and resolve_attributes(ash_resource, column) != []
  rescue
    _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> false
  end

  @doc """
  Returns mapped scalar field names that do not resolve to real Ash attributes on the compiled
  resource. A returned name may still resolve to a calculation or aggregate; that is exactly
  why it is not implicitly admitted for RDF publication.
  """
  @spec non_attribute_mapped_fields(module(), Resource.t()) :: [atom()]
  def non_attribute_mapped_fields(ash_resource, %Resource{predicate_object_maps: predicate_object_maps}) do
    attributes = mapped_attributes(predicate_object_maps)

    try do
      Enum.filter(attributes, &is_nil(Ash.Resource.Info.attribute(ash_resource, &1)))
    rescue
      # Fail closed: when lookup raises, no mapped attribute is admitted.
      _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> attributes
    end
  end

  # Distinct, non-nil Ash attribute names referenced by predicate-object maps.
  defp mapped_attributes(predicate_object_maps) do
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
    |> mapped_attributes()
    |> Enum.filter(&field_policy_protected?(ash_resource, &1))
  end

  @doc false
  @spec field_policy_protected?(module(), atom()) :: boolean()
  def field_policy_protected?(ash_resource, attribute) do
    Code.ensure_loaded?(Ash.Policy.Info) and
      match?([_ | _], Ash.Policy.Info.field_policies_for_field(ash_resource, attribute))
  rescue
    _ in [ArgumentError, UndefinedFunctionError, FunctionClauseError] -> true
  end
end
