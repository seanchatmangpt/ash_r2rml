# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Domain.Verifier do
  @moduledoc """
  Verifies reference object maps across the resources of an `Ash.Domain`.
  """

  use Spark.Dsl.Verifier

  alias AshR2RML.Mapping
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    domain = Verifier.get_persisted(dsl, :module)

    members = Ash.Domain.Info.resources(dsl)

    mappings = Map.new(members, fn resource -> {resource, resolve(resource)} end)

    strict? = Verifier.get_option(dsl, [:r2rml_domain], :strict?, false)

    prefixes =
      Verifier.get_option(
        dsl,
        [:r2rml_domain],
        :allowed_iri_prefixes,
        AshR2RML.Domain.default_allowed_prefixes()
      ) || AshR2RML.Domain.default_allowed_prefixes()

    prefix_errors = if strict?, do: validate_prefixes(prefixes), else: []

    # An invalid allowlist is refused outright; matching against it is moot.
    strict_prefixes = if prefix_errors == [], do: prefixes, else: []

    errors =
      mappings
      |> Enum.flat_map(fn
        {resource, %Mapping.Resource{} = mapping} ->
          check(resource, mapping, members, mappings) ++
            if(strict?, do: strict_check(resource, mapping, strict_prefixes), else: [])

        {_resource, _failure} ->
          []
      end)
      |> Kernel.++(prefix_errors)
      |> Enum.uniq()
      |> Enum.sort()

    case errors do
      [] ->
        :ok

      [_ | _] ->
        {:error,
         Spark.Error.DslError.exception(
           module: domain,
           path: [:resources],
           message: Enum.join(errors, "\n")
         )}
    end
  end

  # A member resolves to its mapping, or to the real %Refusal{} so the parent's
  # own refusal is surfaced, not masked. Referencing the member module waits on
  # the parallel compiler; no explicit compile call is needed.
  defp resolve(resource) do
    case AshR2RML.Resource.Info.mapping_result(resource) do
      {:ok, %Mapping.Resource{} = mapping} -> mapping
      {:error, %AshR2RML.Refusal{} = refusal} -> refusal
    end
  end

  @doc false
  @spec check(module(), Mapping.Resource.t(), [module()], map()) :: [String.t()]
  def check(resource, mapping, members, mappings) do
    Enum.flat_map(mapping.reference_object_maps || [], fn ref ->
      parent = ref.parent_resource
      label = "#{inspect(resource)}.#{inspect(ref.relationship)}"

      if parent in members do
        parent_errors(label, resource, mapping, ref, Map.get(mappings, parent))
      else
        ["#{label}: parent resource #{inspect(parent)} is not in the domain"]
      end
    end)
  end

  # Checks one reference object map against its parent's resolved mapping.
  defp parent_errors(label, resource, mapping, ref, %Mapping.Resource{} = parent_mapping) do
    parent = ref.parent_resource

    subject_errors(label, parent, parent_mapping) ++
      column_errors(label, resource, mapping, parent, parent_mapping, ref)
  end

  defp parent_errors(label, _resource, _mapping, ref, nil),
    do: ["#{label}: parent resource #{inspect(ref.parent_resource)} carries no R2RML mapping"]

  defp parent_errors(label, _resource, _mapping, ref, failure) do
    [
      "#{label}: parent resource #{inspect(ref.parent_resource)} failed to map: " <>
        describe(failure)
    ]
  end

  @doc """
  Refusals for an allowlist whose entries are not delimiter-terminated.

  Every prefix must be a non-empty string ending in `/` or `#` (or `:` for
  `urn:` prefixes), so a bare host prefix without a trailing delimiter cannot admit a longer host.
  """
  @spec validate_prefixes(term()) :: [String.t()]
  def validate_prefixes(prefixes) when is_list(prefixes) do
    prefixes
    |> Enum.reject(&valid_prefix?/1)
    |> Enum.map(
      &"strict mode: allowed IRI prefix #{inspect(&1)} must end in \"/\" or \"#\" (or \":\" for urn: prefixes)"
    )
  end

  def validate_prefixes(other),
    do: ["strict mode: allowed_iri_prefixes must be a list of strings, got #{inspect(other)}"]

  defp valid_prefix?(p) when is_binary(p) do
    String.ends_with?(p, ["/", "#"]) or
      (String.starts_with?(p, "urn:") and String.ends_with?(p, ":"))
  end

  defp valid_prefix?(_), do: false

  @doc """
  Strict-mode violations for one mapping, sorted: blank-node subject maps and
  IRIs (class, predicate, graph, constant or template subject, constant or template object) outside
  `prefixes`. Matching is case-sensitive `String.starts_with?/2`.
  """
  @spec strict_check(module(), Mapping.Resource.t(), [String.t()]) :: [String.t()]
  def strict_check(resource, %Mapping.Resource{} = mapping, prefixes) do
    label = inspect(resource)

    blank_errors =
      case mapping.subject_map do
        %{term_type: :blank_node} -> ["#{label}: strict mode forbids blank-node subject maps"]
        %{strategy: :blank_node} -> ["#{label}: strict mode forbids blank-node subject maps"]
        _ -> []
      end

    mapping
    |> iri_uses()
    |> Enum.reject(fn {_kind, iri} -> allowed?(iri, prefixes) end)
    |> Enum.map(fn {kind, iri} ->
      "#{label}: strict mode: #{kind} IRI #{inspect(iri)} is outside the allowed ontology prefixes"
    end)
    |> Kernel.++(blank_errors)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Constant IRIs are checked whole; IRI templates by their literal prefix (text
  # before the first placeholder). Column-valued terms are runtime data.
  defp constant_iri(kind, %{strategy: :constant, term_type: :iri, value: v}), do: [{kind, v}]
  defp constant_iri(kind, %{strategy: :template, term_type: :iri, value: v}), do: [{kind, literal_prefix(v)}]
  defp constant_iri(_kind, _map), do: []

  defp literal_prefix(template), do: template |> String.split("{") |> hd()

  defp allowed?(iri, prefixes), do: Enum.any?(prefixes, &String.starts_with?(iri, &1))

  defp iri_uses(%Mapping.Resource{} = m) do
    subject_graphs = graph_uses(m.subject_map && m.subject_map.graph_maps)

    classes = Enum.map(m.class_iris, &{:class, &1})
    graphs = graph_uses(m.graph_maps)

    poms =
      Enum.flat_map(m.predicate_object_maps, fn pom ->
        [{:predicate, pom.predicate_iri}] ++
          constant_iri(:object, pom.object_map) ++
          graph_uses(pom.graph_maps) ++ graph_uses(pom.object_map && pom.object_map.graph_maps)
      end)

    roms =
      Enum.flat_map(m.reference_object_maps, fn rom ->
        inverse = if rom.inverse_predicate, do: [{:predicate, rom.inverse_predicate}], else: []
        [{:predicate, rom.predicate_iri}] ++ inverse ++ graph_uses(rom.graph_maps)
      end)

    subject = constant_iri(:subject, m.subject_map)

    classes ++ graphs ++ subject_graphs ++ subject ++ poms ++ roms
  end

  # Constant graphs are checked whole; template graphs by their literal prefix
  # (text before the first placeholder); column graphs are runtime data.
  defp graph_uses(nil), do: []

  defp graph_uses(graph_maps) do
    Enum.flat_map(graph_maps, fn
      %{strategy: :constant, value: v} -> [{:graph, v}]
      %{strategy: :template, value: v} -> [{:graph, literal_prefix(v)}]
      _ -> []
    end)
  end

  defp describe(%AshR2RML.Refusal{code: code, detail: detail}), do: "#{code}: #{detail}"
  defp describe(other), do: inspect(other)

  defp subject_errors(label, parent, %Mapping.Resource{subject_map: nil}),
    do: ["#{label}: parent #{inspect(parent)} has no subject map"]

  defp subject_errors(_label, _parent, _mapping), do: []

  defp column_errors(label, child, child_mapping, parent, parent_mapping, ref) do
    parent_columns = known_columns(parent, parent_mapping)
    child_columns = known_columns(child, child_mapping)

    joins = ref.joins || []

    parent_errors =
      joins
      |> Enum.map(& &1.parent)
      |> Enum.reject(&(to_string(&1) in parent_columns))
      |> Enum.map(&"#{label}: parent join column #{inspect(&1)} does not exist on #{inspect(parent)}")

    child_errors =
      joins
      |> Enum.map(& &1.child)
      |> Enum.reject(&(to_string(&1) in child_columns))
      |> Enum.map(&"#{label}: child join column #{inspect(&1)} does not exist on #{inspect(child)}")

    parent_errors ++ child_errors
  end

  # Join conditions carry SOURCE column names (attribute source || name).
  defp known_columns(resource, mapping) do
    attrs =
      resource
      |> Ash.Resource.Info.attributes()
      |> Enum.map(&to_string(&1.source || &1.name))

    object_cols =
      for %{object_map: %{strategy: :column, value: v}} <- mapping.predicate_object_maps, do: to_string(v)

    subject_cols =
      case mapping.subject_map do
        %{strategy: :column, value: v} -> [to_string(v)]
        _ -> []
      end

    attrs ++ object_cols ++ subject_cols
  end
end
