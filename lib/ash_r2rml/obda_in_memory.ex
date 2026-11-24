# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemory do
  @moduledoc """
  In-process OBDA backend for any Ash data layer.

  A SQL-rewriting engine has no analogue for `Ash.DataLayer.Ets` (no SQL surface at all)
  and would bypass Ash policies, field redaction and tenant scoping. Instead this module
  takes the honest path: it **materializes** the real rows of one or more Ash
  resources -- via a real `Ash.read/2` on an `Ash.Query.for_read/4` query, with no data-layer gate of its own -- into a
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
  a SQL join.

  Materialization intentionally supports what R2RML's own admitted correspondence
  table supports: template/column subject maps, datatype-property predicate-object
  maps, and `rr:joinCondition` reference object maps with **one or more** join
  columns -- a genuine composite-key join (`joins: [%JoinCondition{}, %JoinCondition{}, ...]`)
  resolves the object IRI by substituting every child column's real value into the
  parent's own subject template in turn, producing an IRI only when every column pair
  resolves and the resulting candidate is a valid IRI (see `resolve_composite_object_iri/3`).

  An attribute marked `sensitive?: true` on the Ash resource (Ash core's own
  redaction flag, independent of any specific encryption library) is refused by
  default rather than materialized: `Ash.read!/2` returns the real plaintext value
  for a `sensitive?: true` attribute exactly like any other (unlike a field-policy
  denial, which comes back as a real `%Ash.ForbiddenField{}` sentinel Ash itself
  produces -- see `add_predicate_triples/5` below), so without an explicit check
  here that plaintext would flow straight into the materialized RDF graph. This
  mirrors the `:join_table` precedent immediately below: a typed
  `:REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION` refusal, not a silent per-triple
  skip, so the caller is told exactly which resource/attribute was withheld and
  why. Pass `allow_sensitive: true` to `materialize/3`/`materialize_many/2` to
  opt in explicitly when a caller genuinely wants sensitive values in the graph.

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

  @default_max_rows 10_000
  @default_max_triples 100_000

  @doc """
  Materializes real rows read from `ash_resource` (via a real Ash read action)
  into an `RDF.Graph` shaped by `mapping_resource`.

  `opts` supplies the read's `:actor`, `:tenant`, `:authorize?`, `:context` and `:domain`
  (taken into `Ash.Query.for_read/4`; `:action` selects the read action, default the
  primary read) -- `:allow_sensitive` is this module's own option (see moduledoc) -- so this
  always executes a real Ash action against the real data layer -- never a
  fabricated row set. `allow_sensitive: true` opts into materializing attributes
  marked `sensitive?: true`; the default (`false`) refuses instead. The
  `previous_graph:` differential option of `materialize_many/2` flows through here
  unchanged (this function delegates to it).
  """
  @spec materialize(module(), Resource.t(), keyword()) :: {:ok, RDF.Graph.t()} | {:error, Refusal.t()}
  def materialize(ash_resource, %Resource{} = mapping_resource, opts \\ []) when is_atom(ash_resource) do
    materialize_many([{ash_resource, mapping_resource}], opts)
  end

  @doc """
  Materializes several resources into one shared `RDF.Graph`, including relationship
  triples for any `reference_object_maps` whose `parent_resource` is also present in
  `specs` -- this is what lets one SPARQL query join across resources.

  `opts` applies uniformly to every resource's `Ash.read/2` call (e.g. a shared
  `domain:`/`actor:`), minus `:allow_sensitive` (see `materialize/3`); pass distinct
  options per resource by reading each resource's rows yourself and preferring
  `query/4`'s single-resource form instead if that's needed.

  Pass `previous_graph: %RDF.Graph{}` to also get the differential projection: the
  return becomes `{:ok, %{graph: graph, delta: AshR2RML.Delta.t()}}` where `delta`
  is `AshR2RML.Delta.diff/2` between `previous_graph` (old) and the freshly
  materialized graph (new) -- including its `root_digest`. Without the option the
  return is the historical `{:ok, graph}` unchanged.
  """
  @spec materialize_many([spec()], keyword()) ::
          {:ok, RDF.Graph.t()} | {:ok, %{graph: RDF.Graph.t(), delta: AshR2RML.Delta.t()}} | {:error, Refusal.t()}
  def materialize_many(specs, opts \\ []) when is_list(specs) do
    {result, _stats} = materialize_many_with_stats(specs, opts)
    result
  end

  # Bounds (all read from `opts`, stripped before the Ash read):
  #   * `:max_rows` (default #{@default_max_rows}) -- rows read per resource; the read is
  #     limited to `max_rows + 1` and a surplus row is a typed refusal.
  #   * `:max_triples` (default #{@default_max_triples}) -- accumulation halts as soon as the
  #     emitted triple count exceeds the limit, before any sorting or SPARQL execution.
  #   * `:subject_iri` -- constant subject IRI; with exactly one spec and an invertible
  #     template it is pushed down as a key filter (point lookup reads one row). If the IRI
  #     does not invert, the read is not narrowed.
  # `triples_emitted` counts triples produced per row before cross-row de-duplication.
  defp materialize_many_with_stats(specs, opts) do
    allow_sensitive? = Keyword.get(opts, :allow_sensitive, false)
    previous_graph = Keyword.get(opts, :previous_graph)
    max_triples = Keyword.get(opts, :max_triples, @default_max_triples)

    read_opts =
      opts
      |> Keyword.drop([:allow_sensitive, :previous_graph, :max_triples])
      |> Keyword.put_new(:max_rows, @default_max_rows)
      |> Keyword.put(:pushdown_ok, match?([_], specs))

    # guard options (:allow_unauthorized, :require_*) are consumed and stripped in read_rows/2

    admitted_specs =
      Enum.map(specs, fn {ash_resource, mapping_resource} ->
        {ash_resource, Security.sanitize_in_memory_mapping(ash_resource, mapping_resource)}
      end)

    mapping_index =
      Map.new(admitted_specs, fn {ash_resource, mapping_resource} -> {ash_resource, mapping_resource} end)

    {base_result, stats} =
      Enum.reduce_while(
        admitted_specs,
        {{:ok, RDF.Graph.new()}, %{rows_read: 0, triples_emitted: 0}},
        fn {ash_resource, mapping_resource}, {{:ok, graph_acc}, stats} ->
          case rows_for(ash_resource, mapping_resource, read_opts) do
            {:ok, rows} ->
              stats = %{stats | rows_read: stats.rows_read + length(rows)}

              case add_rows(
                     rows,
                     graph_acc,
                     stats.triples_emitted,
                     max_triples,
                     ash_resource,
                     mapping_resource,
                     mapping_index,
                     allow_sensitive?
                   ) do
                {:ok, graph, emitted} ->
                  {:cont, {{:ok, graph}, %{stats | triples_emitted: emitted}}}

                {:error, refusal, emitted} ->
                  {:halt, {{:error, refusal}, %{stats | triples_emitted: emitted}}}
              end

            {:error, refusal} ->
              {:halt, {{:error, refusal}, stats}}
          end
        end
      )

    result =
      case {base_result, previous_graph} do
        {{:ok, graph}, nil} ->
          {:ok, graph}

        {{:ok, graph}, %RDF.Graph{} = old_graph} ->
          {:ok, %{graph: graph, delta: AshR2RML.Delta.diff(old_graph, graph)}}

        {{:error, refusal}, _} ->
          {:error, refusal}
      end

    {result, stats}
  end

  @doc """
  Materializes `ash_resource`/`mapping_resource` and executes `sparql` against the
  resulting real RDF graph, returning an `Observation` shaped identically to the
  observations `AshR2RML.SPARQL.Local` already produces.
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
    {result, _stats} = query_with_stats(specs, sparql, read_opts)
    result
  end

  @doc """
  Like `query_many/3`, additionally returning `%{rows_read: n, triples_emitted: n}`.
  The stats are returned on refusals too (counts reached when the bound tripped).

  Options: `max_rows` (default #{@default_max_rows}, refusal `:REFUSED_RESULT_LIMIT_EXCEEDED`),
  `max_triples` (default #{@default_max_triples}, refusal `:REFUSED_TRIPLE_LIMIT_EXCEEDED`),
  and `subject_iri` (constant subject IRI pushed down as a key filter for a single spec).
  """
  @spec query_with_stats([spec()], String.t(), keyword()) ::
          {{:ok, Observation.t()} | {:error, Refusal.t()},
           %{rows_read: non_neg_integer(), triples_emitted: non_neg_integer()}}
  def query_with_stats(specs, sparql, read_opts \\ []) when is_list(specs) and is_binary(sparql) do
    case materialize_many_with_stats(specs, read_opts) do
      {{:ok, %RDF.Graph{} = graph}, stats} ->
        query_with_stats_graph(graph, sparql, stats)

      {{:ok, %{graph: graph}}, stats} ->
        query_with_stats_graph(graph, sparql, stats)

      {{:error, _} = error, stats} ->
        {error, stats}
    end
  end

  defp query_with_stats_graph(graph, sparql, stats) do
    case Local.query(graph, sparql) do
      {:ok, observation} ->
        observation = canonical_order(observation, sparql)
        {{:ok, %{observation | metadata: Map.put(observation.metadata, :engine, :in_memory_ets)}}, stats}

      {:error, _} = error ->
        {error, stats}
    end
  end

  # PRD PR-06: without ORDER BY, SELECT row order is unspecified; sort canonically so output
  # is independent of data-layer scan order. With ORDER BY the engine's order is preserved.
  defp canonical_order(%Observation{result_kind: :bindings, rows: rows} = observation, sparql) do
    if Regex.match?(~r/\bORDER\s+BY\b/i, sparql) do
      observation
    else
      %{observation | rows: Enum.sort_by(rows, fn row -> row |> Enum.to_list() |> Enum.sort() end)}
    end
  end

  defp canonical_order(observation, _sparql), do: observation

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
        read_rows(ash_resource, Keyword.put(read_opts, :pushdown, pushdown_keys(mapping_resource, read_opts)))
    end
  end

  # Trivial pushdown: a constant `:subject_iri` inverted through the template subject map
  # into key attribute values. Only for a single-spec call (a filter must not starve a join
  # partner). A non-invertible IRI yields no pushdown -- the read is simply not narrowed.
  defp pushdown_keys(%Resource{subject_map: %SubjectMap{strategy: :template}} = mapping, read_opts) do
    with true <- read_opts[:pushdown_ok] == true,
         iri when is_binary(iri) <- read_opts[:subject_iri],
         {:ok, keys} when map_size(keys) > 0 <- AshR2RML.Subject.from_iri(mapping, iri) do
      Map.to_list(keys)
    else
      _ -> nil
    end
  end

  defp pushdown_keys(_mapping, _read_opts), do: nil

  defp apply_pushdown(query, nil), do: query

  defp apply_pushdown(query, keys) do
    filtered = Ash.Query.do_filter(query, keys)
    if filtered.valid?, do: filtered, else: query
  end

  # Result-tuple read path: every Ash error class (Forbidden, Invalid, Unknown, ...) is a
  # fail-closed refusal; the rescue is only for programmer errors (e.g. no primary read
  # action, malformed options) raised before Ash can return a tuple.
  defp read_rows(ash_resource, read_opts) do
    {guard_opts, read_opts} =
      Keyword.split(read_opts, [:allow_unauthorized, :require_authorizer, :require_tenant])

    read_opts =
      Keyword.update(read_opts, :authorize?, true, fn
        nil -> true
        value -> value
      end)

    with :ok <- check_read_guards(ash_resource, guard_opts, read_opts) do
      do_read_rows(ash_resource, read_opts)
    end
  end

  defp check_read_guards(ash_resource, guard_opts, read_opts) do
    cond do
      read_opts[:authorize?] == false and guard_opts[:allow_unauthorized] != true ->
        guard_refusal(ash_resource, "authorize?: false requires allow_unauthorized: true")

      guard_opts[:require_authorizer] == true and
          Ash.Policy.Authorizer not in Ash.Resource.Info.authorizers(ash_resource) ->
        guard_refusal(ash_resource, "require_authorizer: true but resource has no Ash.Policy.Authorizer")

      guard_opts[:require_tenant] == true and Ash.Resource.Info.multitenancy_strategy(ash_resource) != nil and
          is_nil(read_opts[:tenant]) ->
        guard_refusal(ash_resource, "require_tenant: true but no :tenant given for multitenant resource")

      true ->
        :ok
    end
  end

  defp guard_refusal(ash_resource, message), do: {:error, read_refusal(ash_resource, message, %{})}

  defp do_read_rows(ash_resource, read_opts) do
    action = Keyword.get_lazy(read_opts, :action, fn -> Ash.Resource.Info.primary_action!(ash_resource, :read).name end)

    query =
      Ash.Query.for_read(
        ash_resource,
        action,
        %{},
        Keyword.take(read_opts, [:actor, :tenant, :authorize?, :context, :domain])
      )

    max_rows = Keyword.get(read_opts, :max_rows, @default_max_rows)

    query =
      query
      |> apply_pushdown(read_opts[:pushdown])
      |> Ash.Query.limit(max_rows + 1)

    case Ash.read(query, Keyword.take(read_opts, [:actor, :tenant, :authorize?, :domain])) do
      {:ok, rows} when is_list(rows) and length(rows) > max_rows ->
        {:error,
         Refusal.new(
           :REFUSED_RESULT_LIMIT_EXCEEDED,
           ash_resource,
           "read returned more than max_rows (#{max_rows}) rows; refusing to materialize",
           %{resource: ash_resource, limit: max_rows}
         )}

      {:ok, rows} when is_list(rows) ->
        {:ok, Enum.map(rows, &Map.from_struct/1)}

      {:ok, other} ->
        {:error,
         read_refusal(ash_resource, "unexpected non-list read result", %{
           result_type: if(is_struct(other), do: inspect(other.__struct__), else: "non-struct")
         })}

      {:error, error} ->
        class = if is_exception(error), do: error.__struct__, else: error

        {:error,
         read_refusal(
           ash_resource,
           "fail-closed: could not read the real Ash resource for materialization (#{inspect(class)}, e.g. forbidden by policy)",
           %{error_class: inspect(class), exception: error_message(error)}
         )}
    end
  rescue
    exception in [ArgumentError, RuntimeError, KeyError] ->
      {:error,
       read_refusal(
         ash_resource,
         "fail-closed: could not read the real Ash resource for materialization (#{inspect(exception.__struct__)})",
         %{error_class: inspect(exception.__struct__), exception: Exception.message(exception)}
       )}
  end

  defp read_refusal(ash_resource, message, evidence) do
    Refusal.new(:REFUSED_UNSUPPORTED_SPARQL_FEATURE, ash_resource, message, evidence)
  end

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(error), do: inspect(error)

  # Returns `{:ok, graph}` | `{:error, refusal}` -- a `:join_table` reference object map
  # (see `add_reference_triples/4`) surfaces as a real refusal now, so every caller between
  # here and `materialize_many/2` must be able to propagate it rather than only ever
  # returning a bare graph.
  #
  # Each row is built into its own small graph so its triple count is cheap; the running
  # `emitted` total halts accumulation the moment it exceeds `max_triples`.
  defp add_rows(rows, graph_acc, emitted0, max_triples, ash_resource, mapping_resource, mapping_index, allow_sensitive?) do
    Enum.reduce_while(rows, {:ok, graph_acc, emitted0}, fn row, {:ok, acc, emitted} ->
      case add_row(RDF.Graph.new(), row, ash_resource, mapping_resource, mapping_index, allow_sensitive?) do
        {:ok, row_graph} ->
          emitted = emitted + RDF.Graph.triple_count(row_graph)

          if emitted > max_triples do
            {:halt,
             {:error,
              Refusal.new(
                :REFUSED_TRIPLE_LIMIT_EXCEEDED,
                ash_resource,
                "materialization exceeded max_triples (#{max_triples}); refusing",
                %{resource: ash_resource, limit: max_triples}
              ), emitted}}
          else
            {:cont, {:ok, RDF.Graph.add(acc, row_graph), emitted}}
          end

        {:error, refusal} ->
          {:halt, {:error, refusal, emitted}}
      end
    end)
  end

  defp add_row(graph, row, ash_resource, %Resource{} = mapping_resource, mapping_index, allow_sensitive?) do
    with :ok <- check_subject_sensitive(mapping_resource.subject_map, ash_resource, allow_sensitive?),
         :ok <- check_joins_sensitive(mapping_resource.reference_object_maps, ash_resource, allow_sensitive?) do
      case subject_iri(mapping_resource.subject_map, row) do
        nil ->
          {:ok, graph}

        subject ->
          graph = add_class_triples(graph, subject, mapping_resource.class_iris)

          with {:ok, graph} <-
                 add_predicate_triples(
                   graph,
                   subject,
                   row,
                   mapping_resource.predicate_object_maps,
                   ash_resource,
                   allow_sensitive?
                 ) do
            add_reference_triples(graph, subject, row, mapping_resource.reference_object_maps, mapping_index)
          end
      end
    end
  end

  defp check_subject_sensitive(_subject_map, _ash_resource, true), do: :ok

  defp check_subject_sensitive(%SubjectMap{strategy: :template, value: template}, ash_resource, false) do
    ~r/\{([a-zA-Z0-9_]+)\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> Enum.map(fn [field] -> field end)
    |> check_fields_sensitive(ash_resource, "subject template")
  end

  defp check_subject_sensitive(%SubjectMap{strategy: :column, value: column}, ash_resource, false) do
    check_fields_sensitive([to_string(column)], ash_resource, "subject column")
  end

  defp check_subject_sensitive(_subject_map, _ash_resource, false), do: :ok

  defp check_joins_sensitive(_references, _ash_resource, true), do: :ok

  defp check_joins_sensitive(references, ash_resource, false) do
    references
    |> Enum.flat_map(fn %ReferenceObjectMap{joins: joins} -> Enum.map(joins, &to_string(&1.child)) end)
    |> check_fields_sensitive(ash_resource, "join child column")
  end

  defp field_sensitive?(ash_resource, field) do
    sensitive_attribute?(ash_resource, String.to_existing_atom(field))
  rescue
    ArgumentError -> false
  end

  defp check_fields_sensitive(fields, ash_resource, where) do
    case Enum.find(fields, &field_sensitive?(ash_resource, &1)) do
      nil ->
        :ok

      field ->
        {:error,
         Refusal.new(
           :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
           ash_resource,
           "attribute #{inspect(field)} is marked sensitive?: true on the Ash resource and cannot be used in a #{where} without allow_sensitive: true",
           %{attribute: field}
         )}
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
  # Confirmed against a live external R2RML engine that this is exactly what a compliant
  # engine does *not* do: its `rr:template` substitution percent-encodes the
  # substituted value (`>` -> `%3E`, space -> `%20`, `:`/`/` -> `%3A`/`%2F`, RFC 3986
  # unreserved characters left literal) rather than rejecting the row. This mirrors that
  # behavior with `URI.char_unreserved?/1` so a malicious value is neutralized *and the row is
  # preserved* -- matching that projection instead of only failing safe. The static
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
  defp add_predicate_triples(graph, subject, row, predicate_object_maps, ash_resource, allow_sensitive?) do
    Enum.reduce_while(predicate_object_maps, {:ok, graph}, fn
      %PredicateObjectMap{attribute: nil}, {:ok, acc} ->
        {:cont, {:ok, acc}}

      %PredicateObjectMap{attribute: attribute, predicate_iri: predicate_iri}, {:ok, acc} ->
        case readable(Map.get(row, attribute)) do
          nil ->
            {:cont, {:ok, acc}}

          value ->
            if not allow_sensitive? and sensitive_attribute?(ash_resource, attribute) do
              {:halt,
               {:error,
                Refusal.new(
                  :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
                  ash_resource,
                  "attribute #{inspect(attribute)} is marked sensitive?: true on the Ash resource and cannot be materialized into the RDF graph without allow_sensitive: true",
                  %{attribute: attribute}
                )}}
            else
              {:cont, {:ok, RDF.Graph.add(acc, {RDF.iri(subject), RDF.iri(predicate_iri), rdf_literal(value)})}}
            end
        end
    end)
  end

  defp sensitive_attribute?(ash_resource, attribute) do
    case Ash.Resource.Info.attribute(ash_resource, attribute) do
      %{sensitive?: true} -> true
      _ -> false
    end
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
