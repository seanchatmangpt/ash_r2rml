# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemory do
  @moduledoc """
  In-process OBDA counterpart to `AshR2RML.OBDA.Ontop`, for any Ash data layer Ontop
  cannot reach.

  Ontop rewrites SPARQL to SQL against a JDBC-connected relational database; that
  has no analogue for `Ash.DataLayer.Ets` (no SQL surface at all) or, in fact, any
  non-JDBC-reachable Ash data layer. Instead of faking Ontop, this module takes the
  opposite, honest path: it **materializes** the real rows of one or more Ash
  resources -- via a real `Ash.read!/2`, with no data-layer gate of its own -- into a
  real `RDF.Graph` using the canonical mapping IR (`AshR2RML.Mapping.Resource`, the
  same IR the R2RML renderer consumes), then executes the query with the
  already-existing `AshR2RML.SPARQL.Local` engine (`SPARQL.ex`, full SPARQL
  algebra) against that graph. No hand-rolled query language, no partial BGP
  matcher standing in for SPARQL.

  Before any read result reaches graph construction, each mapping is passed through
  `AshR2RML.Security.sanitize_in_memory_mapping/2`. That is an admission boundary, not
  post-hoc redaction: a mapped field that no longer resolves to a real Ash attribute
  (for example an `ash_cloak` encrypted attribute replaced by a decrypting calculation)
  is structurally absent from the materialization mapping. A calculation becoming loaded
  by default therefore does not manufacture RDF-publication authority for its plaintext.

  Because there is no data-layer check anywhere in this module, it works against any
  real Ash data layer a resource happens to use -- confirmed for real (not just by
  absence-of-a-check) against `Ash.DataLayer.Ets`, `AshCsv.DataLayer`, and
  `AshCubDB.DataLayer` in `test/obda_in_memory_other_data_layers_test.exs`. The
  "ETS-side" framing in earlier revisions of this moduledoc undersold that generality.

  `query/4` / `materialize/3` handle one resource. `query_many/2` / `materialize_many/2`
  merge several resources' triples into a single graph -- including real `rr:RefObjectMap`
  relationship triples resolved from each resource's `reference_object_maps` against the
  other resources in the same call -- so one SPARQL query can traverse a real Ash
  relationship (e.g. `Person -[memberOf]-> Organization`) the same way it would through
  Ontop's SQL join.

  Materialization intentionally supports what R2RML's own admitted correspondence
  table supports: template/column subject maps, datatype-property predicate-object
  maps, and `rr:joinCondition` reference object maps with **one or more** join
  columns -- a genuine composite-key join (`joins: [%JoinCondition{}, %JoinCondition{}, ...]`)
  resolves the object IRI by substituting every child column's real value into the
  parent's own subject template in turn, producing an IRI only when every column pair
  resolves and the resulting candidate is a valid IRI (see `resolve_composite_object_iri/3`).

  The one relationship shape this module does **not** resolve for real is the
  `:join_table` many-to-many shape (`joins: []`, `metadata.kind == :many_to_many`, per
  `AshR2RML.SemanticAdapter.convert_references/2`): the actual FK pairs for that shape
  live on a bridge table that is never itself a mapped Ash resource anywhere in a
  `materialize_many/2` call, so there is no real row data here to resolve the join
  against without fabricating it. This is deliberately a typed
  `:REFUSED_UNSUPPORTED_SPARQL_FEATURE` refusal returned from `materialize/3` and
  `materialize_many/2`, not a silent skip -- the caller is told exactly which
  relationship was dropped and why, rather than discovering a missing edge in the
  materialized graph with no signal at all. Anything else the current mapping IR does
  not model (e.g. custom graph maps beyond the default graph) remains a typed refusal
  or a silently-skipped triple, never a fabricated one.
  """

  alias AshR2RML.Mapping.{JoinCondition, PredicateObjectMap, ReferenceObjectMap, Resource, SubjectMap}
  alias AshR2RML.Refusal
  alias AshR2RML.Security
  alias AshR2RML.SPARQL.{Local, Observation}

  @type spec :: {ash_resource :: module(), mapping_resource :: Resource.t()}

  @doc """
  Materializes real rows read from `ash_resource` (via a real Ash read action)
  into an `RDF.Graph` shaped by `mapping_resource`.

  `read_opts` is passed through to `Ash.read!/2` verbatim (e.g. `domain:`,
  `actor:`) so this always executes a real Ash action against the real data layer --
  never a fabricated row set.
  """
  @spec materialize(module(), Resource.t(), keyword()) :: {:ok, RDF.Graph.t()} | {:error, Refusal.t()}
  def materialize(ash_resource, %Resource{} = mapping_resource, read_opts \\ []) when is_atom(ash_resource) do
    materialize_many([{ash_resource, mapping_resource}], read_opts)
  end

  @doc """
  Materializes several resources into one shared `RDF.Graph`, including relationship
  triples for any `reference_object_maps` whose `parent_resource` is also present in
  `specs` -- this is what lets one SPARQL query join across resources.

  `read_opts` applies uniformly to every resource's `Ash.read!/2` call (e.g. a shared
  `domain:`/`actor:`); pass distinct options per resource by reading each resource's
  rows yourself and preferring `query/4`'s single-resource form instead if that's needed.
  """
  @spec materialize_many([spec()], keyword()) :: {:ok, RDF.Graph.t()} | {:error, Refusal.t()}
  def materialize_many(specs, read_opts \\ []) when is_list(specs) do
    admitted_specs =
      Enum.map(specs, fn {ash_resource, mapping_resource} ->
        {ash_resource, Security.sanitize_in_memory_mapping(ash_resource, mapping_resource)}
      end)

    mapping_index =
      Map.new(admitted_specs, fn {ash_resource, mapping_resource} -> {ash_resource, mapping_resource} end)

    Enum.reduce_while(admitted_specs, {:ok, RDF.Graph.new()}, fn {ash_resource, mapping_resource}, {:ok, graph_acc} ->
      with {:ok, rows} <- rows_for(ash_resource, mapping_resource, read_opts),
           {:ok, graph} <- add_rows(rows, graph_acc, mapping_resource, mapping_index) do
        {:cont, {:ok, graph}}
      else
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  @doc """
  Materializes `ash_resource`/`mapping_resource` and executes `sparql` against the
  resulting real RDF graph, returning an `Observation` shaped identically to the
  observations `AshR2RML.OBDA.Ontop` and `AshR2RML.SPARQL.Local` already produce so
  it composes with `AshR2RML.SPARQL.Differential.compare/3`.
  """
  @spec query(module(), Resource.t(), String.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, Refusal.t()}
  def query(ash_resource, %Resource{} = mapping_resource, sparql, read_opts \\ [])
      when is_atom(ash_resource) and is_binary(sparql) do
    query_many([{ash_resource, mapping_resource}], sparql, read_opts)
  end

  @doc """
  Materializes several resources into one graph (see `materialize_many/2`) and executes
  one SPARQL query across all of them -- a real cross-resource join, resolved from the
  same mapping IR every other rendering surface uses.
  """
  @spec query_many([spec()], String.t(), keyword()) :: {:ok, Observation.t()} | {:error, Refusal.t()}
  def query_many(specs, sparql, read_opts \\ []) when is_list(specs) and is_binary(sparql) do
    with {:ok, graph} <- materialize_many(specs, read_opts),
         {:ok, observation} <- Local.query(graph, sparql) do
      {:ok, %{observation | metadata: Map.put(observation.metadata, :engine, :in_memory_ets)}}
    end
  end

  defp rows_for(ash_resource, %Resource{} = mapping_resource, read_opts) do
    case mapping_resource.subject_map do
      %SubjectMap{strategy: strategy} when strategy not in [:template, :column] ->
        {:error,
         Refusal.new(
           :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
           mapping_resource.ash_resource,
           "in-memory materialization only supports :template and :column subject map strategies",
           %{strategy: strategy}
         )}

      _subject_map ->
        try do
          {:ok, ash_resource |> Ash.read!(read_opts) |> Enum.map(&Map.from_struct/1)}
        rescue
          exception ->
            {:error,
             Refusal.new(
               :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
               mapping_resource.ash_resource,
               "could not read the real Ash resource for materialization",
               %{exception: Exception.message(exception)}
             )}
        end
    end
  end

  # Returns `{:ok, graph}` | `{:error, refusal}` -- a `:join_table` reference object map
  # (see `add_reference_triples/4`) surfaces as a real refusal now, so every caller between
  # here and `materialize_many/2` must be able to propagate it rather than only ever
  # returning a bare graph.
  defp add_rows(rows, graph_acc, mapping_resource, mapping_index) do
    Enum.reduce_while(rows, {:ok, graph_acc}, fn row, {:ok, acc} ->
      case add_row(acc, row, mapping_resource, mapping_index) do
        {:ok, graph} -> {:cont, {:ok, graph}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp add_row(graph, row, %Resource{} = mapping_resource, mapping_index) do
    case subject_iri(mapping_resource.subject_map, row) do
      nil ->
        {:ok, graph}

      subject ->
        graph
        |> add_class_triples(subject, mapping_resource.class_iris)
        |> add_predicate_triples(subject, row, mapping_resource.predicate_object_maps)
        |> add_reference_triples(subject, row, mapping_resource.reference_object_maps, mapping_index)
    end
  end

  defp subject_iri(%SubjectMap{strategy: :template, value: template}, row) do
    if template_fields_readable?(template, row) do
      template
      |> substitute_template(row)
      |> valid_iri_or_nil()
    else
      nil
    end
  rescue
    ArgumentError -> nil
  end

  defp subject_iri(%SubjectMap{strategy: :column, value: column}, row) do
    case readable(Map.get(row, safe_atom(column))) do
      nil -> nil
      value -> value |> to_string() |> valid_iri_or_nil()
    end
  end

  defp subject_iri(_subject_map, _row), do: nil

  # Every subject/object IRI in this module is built by substituting real row data (attacker-
  # influenced whenever the substituted attribute is a plain writable string, not just a
  # generated UUID) into a template string. `RDF.iri/1` does not validate RFC 3987 syntax on
  # construction, and RDF.ex's Turtle writer does not escape an unescaped `>`/control
  # character inside an IRIREF -- so an unvalidated substituted value (e.g. a name or slug
  # containing `>`) can terminate the IRI early in the serialized Turtle and splice arbitrary
  # extra triples into the document.
  #
  # Confirmed against a live Ontop + PostgreSQL stack that this is exactly what a compliant
  # R2RML engine does *not* do: Ontop's own `rr:template` substitution percent-encodes the
  # substituted value (`>` -> `%3E`, space -> `%20`, `:`/`/` -> `%3A`/`%2F`, RFC 3986
  # unreserved characters left literal) rather than rejecting the row. This mirrors that
  # behavior with `URI.char_unreserved?/1` so a malicious value is neutralized *and the row is
  # preserved* -- matching Ontop's projection instead of only failing safe. The static
  # (author-written) portion of the template is never encoded, only the substituted value.
  defp substitute_template(template, row) do
    Regex.replace(~r/\{([a-zA-Z0-9_]+)\}/, template, fn _whole, field ->
      row |> Map.get(String.to_existing_atom(field)) |> to_string() |> percent_encode_iri_value()
    end)
  end

  defp percent_encode_iri_value(value), do: URI.encode(value, &URI.char_unreserved?/1)

  # `:column` subject/object maps are different in kind from `:template`: the column's value
  # IS the entire IRI as stored (R2RML's `rr:column` term-type-iri semantics), not a value
  # embedded inside an author-written template. There is nothing to percent-encode without
  # changing already-valid stored IRIs, so this path stays fail-closed: a malformed stored
  # value means the row's own data is not a well-formed IRI, and is skipped rather than
  # rewritten.
  defp valid_iri_or_nil(candidate) do
    if valid_iri?(candidate), do: candidate, else: nil
  end

  defp valid_iri?(value) when is_binary(value) do
    value |> RDF.iri() |> RDF.IRI.valid?()
  rescue
    _ -> false
  end

  defp valid_iri?(_value), do: false

  # A denied/unloaded field inside a subject template (unusual, but the mapping IR does not
  # forbid it) would otherwise crash `to_string/1` on the sentinel struct; that must fail
  # closed (no subject at all -- the row is simply not materializable for this actor) rather
  # than leak a stringified struct into an IRI.
  defp template_fields_readable?(template, row) do
    ~r/\{([a-zA-Z0-9_]+)\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> Enum.all?(fn [field] -> readable(Map.get(row, String.to_existing_atom(field))) != nil end)
  rescue
    ArgumentError -> false
  end

  defp readable(%Ash.ForbiddenField{}), do: nil
  defp readable(%Ash.NotLoaded{}), do: nil
  defp readable(value), do: value

  defp add_class_triples(graph, subject, class_iris) do
    Enum.reduce(class_iris, graph, fn class_iri, acc ->
      RDF.Graph.add(
        acc,
        {RDF.iri(subject), RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), RDF.iri(class_iri)}
      )
    end)
  end

  # `Ash.read!/2` honors real Ash policies (resource-level and field-level) on the actor
  # passed through `read_opts` -- exactly as it would in any other Ash caller. A field a
  # field policy denies to the given actor does not come back as `nil`; it comes back as a
  # real `%Ash.ForbiddenField{}` sentinel struct (an unloaded/not-yet-selected attribute
  # comes back as `%Ash.NotLoaded{}` the same way). Materialization must treat both the same
  # way Ash's own JSON/GraphQL serializers do: omit the triple entirely, never stringify the
  # sentinel struct into a fake literal value. This is what makes a field policy (e.g. "only
  # :admin can read :secret_key") carry through into the RDF projection without extra code
  # at each call site -- security is enforced once, by Ash, and respected here rather than
  # bypassed.
  defp add_predicate_triples(graph, subject, row, predicate_object_maps) do
    Enum.reduce(predicate_object_maps, graph, fn
      %PredicateObjectMap{attribute: nil}, acc ->
        acc

      %PredicateObjectMap{attribute: attribute, predicate_iri: predicate_iri}, acc ->
        case readable(Map.get(row, attribute)) do
          nil -> acc
          value -> RDF.Graph.add(acc, {RDF.iri(subject), RDF.iri(predicate_iri), rdf_literal(value)})
        end
    end)
  end

  # A single-column join and a genuine composite-key join (2+ `JoinCondition` entries) are
  # resolved by the same mechanism: every column pair's real child value is substituted for
  # its matching placeholder in the *parent* resource's own subject template, in order, so
  # the object IRI is identical to the IRI that resource would materialize as a subject in
  # its own right -- the same identity, reached two ways. This produces an object IRI only
  # when every column pair's child value is present (`readable/1`) and every corresponding
  # parent-field substitution succeeds (`substitute_field/3`) and the resulting candidate is
  # a well-formed IRI (`valid_iri?/1`) -- see `resolve_composite_object_iri/3`. A join whose
  # parent resource wasn't included in this call, or whose FK value is nil, or whose
  # substitution/validation fails at any column, is silently skipped (not fabricated): the
  # relationship simply isn't traversable from the data given, exactly as it wouldn't be over
  # a real SQL LEFT JOIN with no matching row.
  #
  # The one shape that is NOT silently skipped is `joins: []` -- the `:join_table`
  # many-to-many relationship shape (see moduledoc): that surfaces as a real
  # `{:error, refusal}` instead, propagated all the way out through `materialize_many/2`.
  defp add_reference_triples(graph, subject, row, reference_object_maps, mapping_index) do
    Enum.reduce_while(reference_object_maps, {:ok, graph}, fn reference, {:ok, acc} ->
      case resolve_reference_object(reference, row, mapping_index) do
        {:ok, nil} ->
          {:cont, {:ok, acc}}

        {:ok, object_iri} ->
          {:cont, {:ok, RDF.Graph.add(acc, {RDF.iri(subject), RDF.iri(reference.predicate_iri), RDF.iri(object_iri)})}}

        {:error, refusal} ->
          {:halt, {:error, refusal}}
      end
    end)
  end

  # `joins: []` is exactly the shape `AshR2RML.SemanticAdapter.convert_references/2`
  # (`lib/ash_r2rml/compiler.ex:604-611`) emits for a `:join_table` many-to-many relationship.
  # There is no bridge-table row data anywhere in `mapping_index` to resolve that join
  # against (the join table is never itself a mapped Ash resource passed to
  # `materialize_many/2`), so this is a typed refusal -- see moduledoc for the full rationale.
  defp resolve_reference_object(%ReferenceObjectMap{joins: []} = reference, _row, _mapping_index) do
    {:error,
     Refusal.new(
       :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
       reference.parent_resource,
       "in-memory materialization does not resolve :join_table (many-to-many) reference object maps -- the join table's own rows are not represented anywhere in the mapping IR handed to materialize_many/2",
       %{relationship: reference.relationship, metadata: reference.metadata}
     )}
  end

  defp resolve_reference_object(%ReferenceObjectMap{joins: joins} = reference, row, mapping_index)
       when joins != [] do
    case Map.fetch(mapping_index, reference.parent_resource) do
      {:ok, parent_mapping} -> {:ok, resolve_composite_object_iri(joins, row, parent_mapping.subject_map)}
      :error -> {:ok, nil}
    end
  end

  # A `:template` parent subject map substitutes each join column's real child value, in
  # turn, into the same placeholder-bearing template used to build that parent's own subject
  # IRI -- this is what makes an N-column composite key differ from the single-column case
  # only in "substitute N fields instead of one" rather than needing a parallel code path.
  defp resolve_composite_object_iri(joins, row, %SubjectMap{strategy: :template} = parent_subject_map) do
    joins
    |> Enum.reduce_while(parent_subject_map.value, fn %JoinCondition{child: child, parent: parent}, template ->
      with child_value when not is_nil(child_value) <- readable(Map.get(row, safe_atom(child))),
           substituted when is_binary(substituted) <-
             substitute_field(%{parent_subject_map | value: template}, parent, child_value) do
        {:cont, substituted}
      else
        _ -> {:halt, nil}
      end
    end)
    |> case do
      nil -> nil
      candidate -> if valid_iri?(candidate), do: candidate, else: nil
    end
  end

  # A `:column` parent subject map has exactly one meaningful field (the column value IS the
  # whole IRI, R2RML `rr:column` term-type-iri semantics) -- only a single-column join
  # resolves against it; 2+ join conditions against a `:column` parent are unresolvable and
  # fall through to the fail-closed clause below.
  defp resolve_composite_object_iri(
         [%JoinCondition{child: child, parent: parent}],
         row,
         %SubjectMap{
           strategy: :column
         } = parent_subject_map
       ) do
    with child_value when not is_nil(child_value) <- readable(Map.get(row, safe_atom(child))),
         object_iri when is_binary(object_iri) <- substitute_field(parent_subject_map, parent, child_value),
         true <- valid_iri?(object_iri) do
      object_iri
    else
      _ -> nil
    end
  end

  defp resolve_composite_object_iri(_joins, _row, _parent_subject_map), do: nil

  defp substitute_field(%SubjectMap{strategy: :template, value: template}, field, value) do
    placeholder = "{#{field}}"

    if String.contains?(template, placeholder) do
      String.replace(template, placeholder, percent_encode_iri_value(to_string(value)))
    else
      nil
    end
  end

  defp substitute_field(%SubjectMap{strategy: :column}, _field, value), do: to_string(value)
  defp substitute_field(_subject_map, _field, _value), do: nil

  defp rdf_literal(value) when is_binary(value), do: RDF.literal(value)
  defp rdf_literal(value), do: RDF.literal(to_string(value))

  defp safe_atom(value) when is_atom(value), do: value
  defp safe_atom(value) when is_binary(value), do: String.to_existing_atom(value)
end
