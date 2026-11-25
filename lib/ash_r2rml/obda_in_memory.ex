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
  materialized graph with no signal at all.

  ## Named graphs (`rr:graphMap`)

  Materialization produces quads. `materialize_dataset/2` returns the `RDF.Dataset`
  (`{s, p, o, g}`; `g == nil` is the default graph) with each triple placed in the graphs its
  resource, subject, predicate-object, object and reference graph maps resolve to for the row.
  `materialize/3` and `materialize_many/2` return the union of all graphs as one
  `RDF.Graph`, and a query without `GRAPH` runs against that union (union default graph).
  `GRAPH <iri> { ... }` and `GRAPH ?g { ... }` are evaluated against the named graphs (see
  `AshR2RML.OBDA.InMemory.GraphQuery` for the supported shapes; others are typed refusals).
  Because rows are read through `Ash.read/2` with the caller's `:actor`/`:tenant`, graph
  content is already scoped to what that actor/tenant may see.
  """

  alias AshR2RML.Mapping.{JoinCondition, ObjectMap, PredicateObjectMap, ReferenceObjectMap, Resource, SubjectMap}
  alias AshR2RML.Refusal
  alias AshR2RML.Security
  alias AshR2RML.Mapping.GraphMap
  alias AshR2RML.OBDA.InMemory.IriTemplate
  alias AshR2RML.SPARQL.{Local, Observation, Query, Result}

  @type spec :: {ash_resource :: module(), mapping_resource :: Resource.t()}

  # A read failing with a real Ash Forbidden/TenantRequired keeps its typed `%AshR2RML.Error{}`
  # (see `AshR2RML.OBDA.classify/1`); every other refusal is an `%AshR2RML.Refusal{}`.
  @type failure :: Refusal.t() | AshR2RML.Error.t()

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
  @spec materialize(module(), Resource.t(), keyword()) ::
          {:ok, RDF.Graph.t()} | {:ok, %{graph: RDF.Graph.t(), delta: AshR2RML.Delta.t()}} | {:error, failure()}
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
          {:ok, RDF.Graph.t()} | {:ok, %{graph: RDF.Graph.t(), delta: AshR2RML.Delta.t()}} | {:error, failure()}
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
    previous_graph = Keyword.get(opts, :previous_graph)

    {dataset_result, stats} = materialize_dataset_with_stats(specs, opts)

    result =
      case {dataset_result, previous_graph} do
        {{:ok, dataset}, nil} ->
          {:ok, union_graph(dataset)}

        {{:ok, dataset}, %RDF.Graph{} = old_graph} ->
          graph = union_graph(dataset)
          {:ok, %{graph: graph, delta: AshR2RML.Delta.diff(old_graph, graph)}}

        {{:error, refusal}, _} ->
          {:error, refusal}
      end

    {result, stats}
  end

  @doc """
  Materializes several resources into one `RDF.Dataset` of quads `{s, p, o, g}`.

  `rr:graphMap`/`rr:graph` placement is enforced here: a triple lands in every named
  graph its resource-, subject-, predicate-object- and object-level graph maps resolve to
  for the row (constant IRI, template or column). A triple with no graph map lands in the
  default graph (graph name `nil`). A graph map that cannot resolve for a row (nil/forbidden
  column, invalid IRI) drops the triple for that graph -- it never falls back to the default
  graph. Reads run under the caller's `:actor`/`:tenant`, so graph content is already
  filtered by Ash policies and tenancy. Same options as `materialize_many/2`
  (`:previous_graph` is ignored).
  """
  @spec materialize_dataset([spec()], keyword()) :: {:ok, RDF.Dataset.t()} | {:error, failure()}
  def materialize_dataset(specs, opts \\ []) when is_list(specs) do
    {result, _stats} = materialize_dataset_with_stats(specs, opts)
    result
  end

  defp union_graph(%RDF.Dataset{} = dataset) do
    dataset
    |> RDF.Dataset.graphs()
    |> Enum.reduce(RDF.Graph.new(), fn graph, acc -> RDF.Graph.add(acc, %{graph | name: nil}) end)
  end

  defp materialize_dataset_with_stats(specs, opts) do
    allow_sensitive? = Keyword.get(opts, :allow_sensitive, false)
    max_triples = Keyword.get(opts, :max_triples, @default_max_triples)

    read_opts =
      opts
      |> Keyword.drop([:allow_sensitive, :previous_graph, :max_triples])
      |> Keyword.put_new(:max_rows, @default_max_rows)
      |> Keyword.put(:pushdown_ok, true)
      |> Keyword.put(:pushdown_parents, referenced_parents(specs))

    # guard options (:allow_unauthorized, :require_*) are consumed and stripped in read_rows/2

    admitted_specs =
      Enum.map(specs, fn {ash_resource, mapping_resource} ->
        {ash_resource, Security.sanitize_in_memory_mapping(ash_resource, mapping_resource)}
      end)

    mapping_index = Map.new(admitted_specs)

    {first_result, stats, pending} =
      Enum.reduce_while(
        admitted_specs,
        {{:ok, RDF.Dataset.new()}, %{rows_read: 0, triples_emitted: 0}, []},
        fn {ash_resource, mapping_resource}, {{:ok, graph_acc}, stats, pending} ->
          budget_opts = Keyword.put(read_opts, :triple_budget, max_triples - stats.triples_emitted)

          case rows_for(ash_resource, mapping_resource, budget_opts) do
            {:ok, rows} ->
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
                {:ok, graph, emitted, n} ->
                  pending = [{ash_resource, mapping_resource, rows} | pending]
                  stats = %{stats | rows_read: stats.rows_read + n, triples_emitted: emitted}
                  {:cont, {{:ok, graph}, stats, pending}}

                {:error, refusal, emitted, n} ->
                  stats = %{stats | rows_read: stats.rows_read + n, triples_emitted: emitted}
                  {:halt, {{:error, refusal}, stats, pending}}
              end

            {:error, refusal} ->
              {:halt, {{:error, refusal}, stats, pending}}
          end
        end
      )

    # Reference objects are resolved only after every resource was read, and only to parent
    # subjects actually materialized in this query (a parent row the actor cannot read must
    # not be disclosed through a child's FK value).
    case first_result do
      {:ok, dataset} ->
        add_reference_pass(
          Enum.reverse(pending),
          dataset,
          stats,
          max_triples,
          mapping_index
        )

      error ->
        {error, stats}
    end
  end

  @doc """
  Materializes `ash_resource`/`mapping_resource` and executes `sparql` against the
  resulting real RDF graph, returning an `Observation` shaped identically to the
  observations `AshR2RML.SPARQL.Local` already produces.
  """
  @spec query(module(), Resource.t(), String.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, failure()}
  def query(ash_resource, %Resource{} = mapping_resource, sparql, read_opts \\ [])
      when is_atom(ash_resource) and is_binary(sparql) do
    query_many([{ash_resource, mapping_resource}], sparql, read_opts)
  end

  @doc """
  Materializes several resources into one graph (see `materialize_many/2`) and executes
  one SPARQL query across all of them -- a real cross-resource join, resolved from the
  same mapping IR every other rendering surface uses.
  """
  @spec query_many([spec()], String.t(), keyword()) :: {:ok, Observation.t()} | {:error, failure()}
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
          {{:ok, Observation.t()} | {:error, failure()},
           %{rows_read: non_neg_integer(), triples_emitted: non_neg_integer()}}
  def query_with_stats(specs, sparql, read_opts \\ []) when is_list(specs) and is_binary(sparql) do
    case materialize_dataset_with_stats(specs, read_opts) do
      {{:ok, %RDF.Dataset{} = dataset}, stats} ->
        case AshR2RML.OBDA.InMemory.GraphQuery.plan(sparql) do
          :none ->
            query_with_stats_graph(union_graph(dataset), sparql, stats, local_opts(read_opts))

          {:ok, plan} ->
            query_graph_plan(dataset, plan, sparql, stats, local_opts(read_opts))

          {:error, message, evidence} ->
            refusal = Refusal.new(:REFUSED_UNSUPPORTED_SPARQL_FEATURE, :graph_pattern, message, evidence)
            {{:error, refusal}, stats}
        end

      {{:error, _} = error, stats} ->
        {error, stats}
    end
  end

  # `GRAPH <iri> { P }`: one execution against that named graph (empty graph when absent).
  defp query_graph_plan(dataset, %{kind: :iri, iri: iri, rewritten: rewritten}, sparql, stats, local_opts) do
    graph = RDF.Dataset.graph(dataset, iri) || RDF.Graph.new()

    case query_with_stats_graph(graph, rewritten, stats, local_opts) do
      {{:ok, observation}, stats} -> {{:ok, reidentify(observation, sparql, :graph_iri)}, stats}
      other -> other
    end
  end

  # `GRAPH ?g { P }`: P is evaluated per named graph with `BIND(<g> AS ?g)` and the
  # per-graph observations are merged.
  defp query_graph_plan(dataset, %{kind: :var, rewrite: rewrite}, sparql, stats, local_opts) do
    names = dataset |> RDF.Dataset.graph_names() |> Enum.reject(&is_nil/1) |> Enum.sort_by(&to_string/1)

    results =
      Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
        graph = RDF.Dataset.graph(dataset, name)

        case query_with_stats_graph(graph, rewrite.(to_string(name)), stats, local_opts) do
          {{:ok, observation}, _stats} -> {:cont, {:ok, [observation | acc]}}
          {{:error, _} = error, _stats} -> {:halt, error}
        end
      end)

    case results do
      {:ok, observations} ->
        merged = merge_observations(Enum.reverse(observations), sparql)
        {bound_merged(merged, local_opts), stats}

      {:error, _} = error ->
        {error, stats}
    end
  end

  # Per-graph executions are each bounded; the merged `GRAPH ?g` solution set is bounded too.
  defp bound_merged(%Observation{rows: rows} = observation, local_opts) do
    max_rows = Keyword.get(local_opts, :max_rows)

    if is_integer(max_rows) and length(rows) > max_rows do
      {:error,
       Refusal.new(
         :REFUSED_RESULT_LIMIT_EXCEEDED,
         :graph_var,
         "merged GRAPH ?g solutions exceed max_rows (#{max_rows}); refusing to return them",
         %{limit: max_rows}
       )}
    else
      {:ok, observation}
    end
  end

  defp reidentify(%Observation{} = observation, sparql, kind) do
    %{
      observation
      | query_sha256: :crypto.hash(:sha256, sparql) |> Base.encode16(case: :lower),
        metadata: Map.put(observation.metadata, :graph_pattern, kind)
    }
  end

  # No named graph exists: `GRAPH ?g { P }` has no solutions (ASK is false).
  defp merge_observations([], sparql) do
    {:ok, admitted} = Query.admit(sparql)

    {kind, rows} =
      case admitted.form do
        :ask -> {:boolean, [%{"ask" => false}]}
        :select -> {:bindings, []}
        _ -> {:rdf, []}
      end

    %Observation{
      strategy: :local_rdf,
      query_sha256: admitted.sha256,
      query_form: admitted.form,
      status: :PARTIAL_ALIVE,
      standing: :observed_local_rdf_execution,
      evidence_kind: :in_memory_execution,
      result_kind: kind,
      result_sha256: Result.hash_rows(rows),
      rows: rows,
      metadata: %{engine: :in_memory_ets}
    }
    |> reidentify(sparql, :graph_var)
  end

  defp merge_observations([first | _] = observations, sparql) do
    rows =
      case first.result_kind do
        :boolean -> [%{"ask" => Enum.any?(observations, fn o -> Enum.any?(o.rows, & &1["ask"]) end)}]
        :rdf -> observations |> Enum.flat_map(& &1.rows) |> Enum.uniq()
        _ -> Enum.flat_map(observations, & &1.rows)
      end

    merged = %{first | rows: rows, result_sha256: Result.hash_rows(rows)}
    merged |> canonical_order(sparql) |> reidentify(sparql, :graph_var)
  end

  # The same `:max_rows` bound the OBDA envelope hands `Local.query/3`, for every graph execution.
  defp local_opts(read_opts) do
    case Keyword.get(read_opts, :max_rows) do
      nil -> []
      max_rows -> [max_rows: max_rows]
    end
  end

  defp query_with_stats_graph(graph, sparql, stats, local_opts) do
    case Local.query(graph, sparql, local_opts) do
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
        read_rows(
          ash_resource,
          read_opts
          |> Keyword.put(:pushdown, pushdown_keys(mapping_resource, read_opts))
          |> Keyword.put(:min_triples_per_row, min_triples_per_row(ash_resource, mapping_resource))
        )
    end
  end

  # Triples every row is *guaranteed* to emit: its class triples plus one per non-nilable column
  # property, provided the subject IRI can never be nil and no field policy can blank a value.
  # Zero (no clamp) whenever any of that is not provable, so the derived read limit never drops a
  # row that would have stayed inside max_triples.
  defp min_triples_per_row(ash_resource, %Resource{} = mapping) do
    with %SubjectMap{strategy: :template, value: template} <- mapping.subject_map,
         true <- template_attrs_non_nil?(ash_resource, template),
         [] <- Ash.Policy.Info.field_policies(ash_resource),
         false <- graph_dependent?(mapping) do
      guaranteed =
        mapping.predicate_object_maps
        |> Enum.uniq_by(& &1.predicate_iri)
        |> Enum.count(fn
          %PredicateObjectMap{attribute: attribute, object_map: %ObjectMap{strategy: :column, term_type: :literal}}
          when not is_nil(attribute) ->
            match?(%{allow_nil?: false, sensitive?: false}, Ash.Resource.Info.attribute(ash_resource, attribute))

          _ ->
            false
        end)

      length(Enum.uniq(mapping.class_iris)) + guaranteed
    else
      _ -> 0
    end
  rescue
    _error in [ArgumentError, KeyError] -> 0
  end

  # A graph map that fails to resolve for a row drops that row's triples, and a malformed stored
  # IRI is skipped, so neither can be counted as guaranteed output.
  defp graph_dependent?(%Resource{} = mapping), do: AshR2RML.Security.all_graph_maps(mapping) != []

  # Object-template placeholders must be real attributes: a calculation (e.g. an AshCloak
  # decrypt-by-default calculation) would otherwise leak through an IRI without any sensitivity check.
  defp check_object_template_fields(template, ash_resource) do
    fields = template_fields(template)
    attribute_names = ash_resource |> Ash.Resource.Info.attributes() |> MapSet.new(&Atom.to_string(&1.name))

    case Enum.reject(fields, &MapSet.member?(attribute_names, &1)) do
      [] ->
        :ok

      non_attributes ->
        {:error,
         Refusal.new(
           :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION,
           ash_resource,
           "object template references non-attribute fields #{inspect(non_attributes)}; only real attributes may appear in IRI templates",
           %{fields: non_attributes, template: template}
         )}
    end
  end

  defp template_fields(template) do
    ~r/\{([^}]+)\}/ |> Regex.scan(template, capture: :all_but_first) |> List.flatten()
  end

  defp template_attrs_non_nil?(ash_resource, template) do
    fields = template_fields(template)

    fields != [] and
      Enum.all?(fields, fn field ->
        case Enum.find(Ash.Resource.Info.attributes(ash_resource), &(Atom.to_string(&1.name) == field)) do
          %{allow_nil?: false} -> true
          _ -> false
        end
      end)
  end

  # Mapping resources referenced as a join parent by any spec (including itself).
  defp referenced_parents(specs) do
    specs
    |> Enum.flat_map(fn {_ash, %Resource{reference_object_maps: refs}} ->
      Enum.map(refs, & &1.parent_resource)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # Trivial pushdown: a constant `:subject_iri` inverted through the template subject map
  # into key attribute values. Applied per spec, and never to a resource that another spec (or
  # itself) references as a join parent -- a filter must not starve a join partner. A
  # non-invertible IRI (e.g. another resource's template) yields no pushdown for that spec.
  defp pushdown_keys(%Resource{subject_map: %SubjectMap{strategy: :template}} = mapping, read_opts) do
    with true <- read_opts[:pushdown_ok] == true,
         false <- mapping.ash_resource in Keyword.get(read_opts, :pushdown_parents, []),
         iri when is_binary(iri) <- read_opts[:subject_iri],
         {:ok, keys} when map_size(keys) > 0 <- AshR2RML.Subject.from_iri(mapping, iri) do
      Map.to_list(keys)
    else
      _ -> nil
    end
  end

  defp pushdown_keys(_mapping, _read_opts), do: nil

  # SPARQL filter/sort/limit lowered by `AshR2RML.QueryBuilder` for the ROOT resource. The built
  # query's filter, sort and (already bounded) limit/offset are layered onto the caller's own
  # `for_read` query, so `actor`, `tenant`, `authorize?` and policies stay exactly as supplied.
  defp apply_query_pushdown(query, ash_resource, read_opts) do
    with %{resource: ^ash_resource, mapping: %Resource{} = mapping, plan: plan} <- read_opts[:query_pushdown],
         %Ash.Query{} = built <-
           AshR2RML.QueryBuilder.pushdown_query(ash_resource, mapping, plan,
             actor: read_opts[:actor],
             tenant: read_opts[:tenant],
             max_rows: Keyword.get(read_opts, :max_rows, @default_max_rows),
             row_cap: read_opts[:row_cap]
           ) do
      pushed =
        query
        |> then(fn q -> if built.filter, do: Ash.Query.do_filter(q, built.filter), else: q end)
        |> then(fn q -> if built.sort == [], do: q, else: Ash.Query.sort(q, built.sort) end)
        |> then(fn q -> if built.offset > 0, do: Ash.Query.offset(q, built.offset), else: q end)
        |> Ash.Query.limit(built.limit)

      if pushed.valid?, do: {:ok, pushed}, else: :none
    else
      _ -> :none
    end
  end

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

    min_per_row = Keyword.get(read_opts, :min_triples_per_row, 0)
    budget = Keyword.get(read_opts, :triple_budget)

    triple_cap = AshR2RML.QueryBuilder.triple_row_cap(budget, min_per_row)
    clamp? = is_integer(triple_cap) and triple_cap < max_rows + 1

    limit = if clamp?, do: triple_cap, else: max_rows + 1

    query =
      case apply_query_pushdown(query, ash_resource, Keyword.put(read_opts, :row_cap, triple_cap)) do
        {:ok, pushed} ->
          # QueryBuilder already bounded the read (`min(plan.limit, max_rows + 1, row_cap)`).
          if pushed.limit, do: pushed, else: Ash.Query.limit(pushed, limit)

        :none ->
          query |> apply_pushdown(read_opts[:pushdown]) |> Ash.Query.limit(limit)
      end

    case Ash.read(query, Keyword.take(read_opts, [:actor, :tenant, :authorize?, :domain])) do
      {:ok, rows} when is_list(rows) and clamp? and length(rows) >= triple_cap ->
        # `limit` rows each emit at least `min_per_row` triples: the budget is provably exceeded.
        {:error,
         Refusal.new(
           :REFUSED_TRIPLE_LIMIT_EXCEEDED,
           ash_resource,
           "materialization exceeded max_triples (budget #{budget}); refusing",
           %{resource: ash_resource, limit: budget}
         )}

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
         AshR2RML.Error.new(:REFUSED_READ_FAILED,
           resource: ash_resource,
           details: %{
             action: read_opts[:action],
             error_class: "non-list read result",
             result_type: if(is_struct(other), do: inspect(other.__struct__), else: "non-struct")
           }
         )}

      {:error, error} ->
        class = if is_exception(error), do: error.__struct__, else: error

        case AshR2RML.OBDA.classify(error) do
          {:REFUSED_READ_FAILED, _} ->
            {:error,
             read_refusal(
               ash_resource,
               "fail-closed: could not read the real Ash resource for materialization (#{inspect(class)}, e.g. forbidden by policy)",
               %{resource: ash_resource, action: read_opts[:action], error_class: inspect(class)}
             )}

          {code, resource} ->
            # Real Ash errors (Forbidden, TenantRequired) keep their typed identity.
            {:error,
             AshR2RML.Error.new(code,
               resource: resource || ash_resource,
               details: %{action: read_opts[:action], error_class: inspect(class)}
             )}
        end
    end
  rescue
    exception in [ArgumentError, RuntimeError, KeyError] ->
      {:error,
       AshR2RML.Error.new(:REFUSED_READ_FAILED,
         resource: ash_resource,
         details: %{action: read_opts[:action], error_class: inspect(exception.__struct__)}
       )}
  end

  defp read_refusal(ash_resource, message, evidence) do
    Refusal.new(:REFUSED_UNSUPPORTED_SPARQL_FEATURE, ash_resource, message, evidence)
  end

  # Returns `{:ok, graph, emitted, rows_done}` | `{:error, refusal, emitted, rows_done}`; the
  # counters let the caller keep running statistics even when a row refuses.
  #
  # Each row is built into its own small graph so its triple count is cheap; the running
  # `emitted` total halts accumulation the moment it exceeds `max_triples`.
  defp add_rows(
         rows,
         graph_acc,
         emitted0,
         max_triples,
         ash_resource,
         mapping_resource,
         _mapping_index,
         allow_sensitive?
       ) do
    # Sensitivity/schema checks depend only on the spec, so they run once per spec (and only
    # when there is at least one row, as before), not once per row.
    case check_spec_sensitive(rows, mapping_resource, ash_resource, allow_sensitive?) do
      :ok ->
        add_checked_rows(
          rows,
          graph_acc,
          emitted0,
          max_triples,
          ash_resource,
          mapping_resource,
          allow_sensitive?
        )

      {:error, refusal} ->
        {:error, refusal, emitted0, 0}
    end
  end

  defp check_spec_sensitive([], _mapping_resource, _ash_resource, _allow_sensitive?), do: :ok

  defp check_spec_sensitive(_rows, %Resource{} = mapping_resource, ash_resource, allow_sensitive?) do
    with :ok <- check_subject_sensitive(mapping_resource.subject_map, ash_resource, allow_sensitive?),
         :ok <- check_joins_sensitive(mapping_resource.reference_object_maps, ash_resource, allow_sensitive?) do
      check_graphs_sensitive(mapping_resource, ash_resource, allow_sensitive?)
    end
  end

  defp add_checked_rows(
         rows,
         graph_acc,
         emitted0,
         max_triples,
         ash_resource,
         mapping_resource,
         allow_sensitive?
       ) do
    rows
    |> Enum.reduce_while({:ok, graph_acc, emitted0, 0}, fn row, {:ok, acc, emitted, n} ->
      case add_row(RDF.Dataset.new(), row, ash_resource, mapping_resource, allow_sensitive?) do
        {:ok, row_graph} ->
          emitted = emitted + RDF.Dataset.statement_count(row_graph)

          if emitted > max_triples do
            {:halt,
             {:error,
              Refusal.new(
                :REFUSED_TRIPLE_LIMIT_EXCEEDED,
                ash_resource,
                "materialization exceeded max_triples (#{max_triples}); refusing",
                %{resource: ash_resource, limit: max_triples}
              ), emitted, n + 1}}
          else
            {:cont, {:ok, RDF.Dataset.add(acc, row_graph), emitted, n + 1}}
          end

        {:error, refusal} ->
          {:halt, {:error, refusal, emitted, n}}
      end
    end)
  end

  defp add_reference_pass(pending, graph, stats, max_triples, mapping_index) do
    visible =
      Enum.reduce(pending, %{}, fn {ash_resource, mapping, rows}, acc ->
        subjects = for row <- rows, iri = subject_iri(mapping.subject_map, row), into: MapSet.new(), do: iri
        Map.update(acc, ash_resource, subjects, &MapSet.union(&1, subjects))
      end)

    Enum.reduce_while(pending, {{:ok, graph}, stats}, fn {ash_resource, mapping, rows}, acc ->
      refs = mapping.reference_object_maps

      if refs == [] do
        {:cont, acc}
      else
        reference_rows(rows, refs, ash_resource, mapping, mapping_index, visible, max_triples, acc)
      end
    end)
  end

  defp reference_rows(rows, refs, ash_resource, mapping, mapping_index, visible, max_triples, acc) do
    Enum.reduce_while(rows, {:cont, acc}, fn row, {:cont, {{:ok, graph}, stats}} ->
      case subject_iri(mapping.subject_map, row) do
        nil ->
          {:cont, {:cont, {{:ok, graph}, stats}}}

        subject ->
          case add_reference_triples(RDF.Dataset.new(), subject, row, refs, {mapping, mapping_index, visible}) do
            {:ok, ref_graph} ->
              emitted = stats.triples_emitted + RDF.Dataset.statement_count(ref_graph)
              stats = %{stats | triples_emitted: emitted}

              if emitted > max_triples do
                refusal =
                  Refusal.new(
                    :REFUSED_TRIPLE_LIMIT_EXCEEDED,
                    ash_resource,
                    "materialization exceeded max_triples (#{max_triples}); refusing",
                    %{resource: ash_resource, limit: max_triples}
                  )

                {:halt, {:halt, {{:error, refusal}, stats}}}
              else
                {:cont, {:cont, {{:ok, RDF.Dataset.add(graph, ref_graph)}, stats}}}
              end

            {:error, refusal} ->
              {:halt, {:halt, {{:error, refusal}, stats}}}
          end
      end
    end)
  end

  defp add_row(graph, row, ash_resource, %Resource{} = mapping_resource, allow_sensitive?) do
    case subject_iri(mapping_resource.subject_map, row) do
      nil ->
        {:ok, graph}

      subject ->
        class_graphs = graph_names(mapping_resource, [], row)
        graph = add_class_triples(graph, subject, mapping_resource.class_iris, class_graphs)

        # Reference triples are added afterwards by `add_reference_pass/5`.
        add_predicate_triples(graph, subject, row, mapping_resource, ash_resource, allow_sensitive?)
    end
  end

  # Graph names (`nil` = default graph) a triple of this row is placed in. Resource-level,
  # subject-level and the supplied predicate-object/object/reference graph maps all apply.
  # When maps exist but none resolves for the row the result is `[]`: the triple is dropped,
  # never demoted into the default graph.
  defp graph_names(%Resource{} = mapping, extra_maps, row) do
    case mapping.graph_maps ++ mapping.subject_map.graph_maps ++ extra_maps do
      [] -> [nil]
      maps -> maps |> Enum.map(&resolve_graph(&1, row)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    end
  end

  defp resolve_graph(%GraphMap{strategy: :constant, value: value}, _row), do: valid_iri_or_nil(value)

  defp resolve_graph(%GraphMap{strategy: :template, value: template}, row) do
    if template_fields_readable?(template, row) do
      template |> substitute_template(row) |> valid_iri_or_nil()
    end
  rescue
    _error in [ArgumentError, Protocol.UndefinedError] -> nil
  end

  defp resolve_graph(%GraphMap{strategy: :column, value: column}, row) do
    case readable(Map.get(row, safe_atom(column))) do
      nil -> nil
      value -> value |> to_string() |> valid_iri_or_nil()
    end
  rescue
    _error in [ArgumentError, Protocol.UndefinedError] -> nil
  end

  defp resolve_graph(_other, _row), do: nil

  defp add_quads(dataset, subject, predicate, object, graphs) do
    Enum.reduce(graphs, dataset, fn graph_name, acc ->
      graph = if graph_name, do: RDF.iri(graph_name)
      RDF.Dataset.add(acc, {RDF.iri(subject), RDF.iri(predicate), object, graph})
    end)
  end

  defp check_graphs_sensitive(_mapping, _ash_resource, true), do: :ok

  defp check_graphs_sensitive(%Resource{} = mapping, ash_resource, false) do
    all_maps =
      mapping.graph_maps ++
        mapping.subject_map.graph_maps ++
        Enum.flat_map(mapping.predicate_object_maps, &(&1.graph_maps ++ &1.object_map.graph_maps)) ++
        Enum.flat_map(mapping.reference_object_maps, & &1.graph_maps)

    Enum.find_value(all_maps, :ok, fn
      %GraphMap{strategy: strategy, value: value} when strategy in [:template, :column] ->
        case check_subject_sensitive(%SubjectMap{strategy: strategy, value: value}, ash_resource, false) do
          :ok -> nil
          error -> error
        end

      _ ->
        nil
    end)
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

  # Resolved by attribute name OR `source` rename, without minting atoms: a sensitive attribute
  # must not escape the check because a join names it by its storage column.
  defp field_sensitive?(ash_resource, field) do
    ash_resource
    |> Ash.Resource.Info.attributes()
    |> Enum.any?(fn attr ->
      attr.sensitive? == true and
        (Atom.to_string(attr.name) == field or (not is_nil(attr.source) and to_string(attr.source) == field))
    end)
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
    _error in [ArgumentError, Protocol.UndefinedError] -> nil
  end

  defp subject_iri(%SubjectMap{strategy: :column, value: column}, row) do
    case readable(Map.get(row, safe_atom(column))) do
      nil -> nil
      value -> value |> to_string() |> valid_iri_or_nil()
    end
  rescue
    _error in [ArgumentError, Protocol.UndefinedError] -> nil
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
  defp substitute_template(template, row), do: IriTemplate.substitute(template, row)

  defp percent_encode_iri_value(value), do: IriTemplate.encode(value)

  # `:column` subject/object maps are different in kind from `:template`: the column's value
  # IS the entire IRI as stored (R2RML's `rr:column` term-type-iri semantics), not a value
  # embedded inside an author-written template. There is nothing to percent-encode without
  # changing already-valid stored IRIs, so this path stays fail-closed: a malformed stored
  # value means the row's own data is not a well-formed IRI, and is skipped rather than
  # rewritten.
  defp valid_iri_or_nil(candidate), do: IriTemplate.valid_iri_or_nil(candidate)

  defp valid_iri?(value), do: IriTemplate.valid_iri?(value)

  # A denied/unloaded field inside a subject template (unusual, but the mapping IR does not
  # forbid it) would otherwise crash `to_string/1` on the sentinel struct; that must fail
  # closed (no subject at all -- the row is simply not materializable for this actor) rather
  # than leak a stringified struct into an IRI.
  defp template_fields_readable?(template, row), do: IriTemplate.fields_readable?(template, row)

  defp readable(value), do: IriTemplate.readable(value)

  defp add_class_triples(graph, subject, class_iris, graphs) do
    Enum.reduce(class_iris, graph, fn class_iri, acc ->
      add_quads(acc, subject, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", RDF.iri(class_iri), graphs)
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
  defp add_predicate_triples(graph, subject, row, %Resource{} = mapping, ash_resource, allow_sensitive?) do
    Enum.reduce_while(mapping.predicate_object_maps, {:ok, graph}, fn
      %PredicateObjectMap{object_map: %ObjectMap{strategy: :template, term_type: :iri, value: template}} = pom,
      {:ok, acc} ->
        object_map_subject = %SubjectMap{strategy: :template, value: template}

        with :ok <- check_object_template_fields(template, ash_resource),
             :ok <- check_subject_sensitive(object_map_subject, ash_resource, allow_sensitive?) do
          case subject_iri(object_map_subject, row) do
            nil ->
              {:cont, {:ok, acc}}

            object_iri ->
              graphs = graph_names(mapping, pom.graph_maps ++ pom.object_map.graph_maps, row)
              {:cont, {:ok, add_quads(acc, subject, pom.predicate_iri, RDF.iri(object_iri), graphs)}}
          end
        else
          {:error, refusal} -> {:halt, {:error, refusal}}
        end

      %PredicateObjectMap{object_map: %ObjectMap{strategy: :constant, term_type: :iri, value: iri}} = pom, {:ok, acc} ->
        graphs = graph_names(mapping, pom.graph_maps ++ pom.object_map.graph_maps, row)
        {:cont, {:ok, add_quads(acc, subject, pom.predicate_iri, RDF.iri(iri), graphs)}}

      %PredicateObjectMap{object_map: %ObjectMap{strategy: strategy, term_type: term_type}} = pom, {:ok, _acc}
      when strategy in [:template, :constant] ->
        # Never silently literalize an object map this backend cannot render faithfully.
        {:halt,
         {:error,
          Refusal.new(
            :UNSUPPORTED_TERM_TYPE,
            ash_resource,
            "in-memory materialization supports only :iri template/constant object maps; got strategy #{inspect(strategy)} with term type #{inspect(term_type)}",
            %{predicate: pom.predicate_iri, strategy: strategy, term_type: term_type}
          )}}

      %PredicateObjectMap{attribute: nil}, {:ok, acc} ->
        {:cont, {:ok, acc}}

      %PredicateObjectMap{attribute: attribute, predicate_iri: predicate_iri, object_map: object_map} = pom,
      {:ok, acc} ->
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
              case object_term(value, object_map) do
                {:ok, term} ->
                  graphs = graph_names(mapping, pom.graph_maps ++ object_map.graph_maps, row)
                  {:cont, {:ok, add_quads(acc, subject, predicate_iri, term, graphs)}}

                :skip ->
                  {:cont, {:ok, acc}}

                :unsupported ->
                  {:halt,
                   {:error,
                    Refusal.new(
                      :UNSUPPORTED_TERM_TYPE,
                      ash_resource,
                      "in-memory materialization does not render term type #{inspect(object_map.term_type)} for column object maps",
                      %{predicate: predicate_iri, strategy: :column, term_type: object_map.term_type}
                    )}}

                :error ->
                  {:halt,
                   {:error,
                    Refusal.new(
                      :REFUSED_NON_LITERAL_DATATYPE,
                      ash_resource,
                      "attribute #{inspect(attribute)} holds a value with no RDF literal lexical form (#{value_kind(value)})",
                      %{attribute: attribute, value_kind: value_kind(value)}
                    )}}
              end
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
  defp add_reference_triples(graph, subject, row, reference_object_maps, {mapping, mapping_index, visible}) do
    Enum.reduce_while(reference_object_maps, {:ok, graph}, fn reference, {:ok, acc} ->
      case resolve_reference_object(reference, row, mapping_index, visible) do
        {:ok, nil} ->
          {:cont, {:ok, acc}}

        {:ok, object_iri} ->
          graphs = graph_names(mapping, reference.graph_maps, row)
          {:cont, {:ok, add_quads(acc, subject, reference.predicate_iri, RDF.iri(object_iri), graphs)}}

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
  defp resolve_reference_object(%ReferenceObjectMap{joins: []} = reference, _row, _mapping_index, _visible) do
    {:error,
     Refusal.new(
       :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
       reference.parent_resource,
       "in-memory materialization does not resolve :join_table (many-to-many) reference object maps -- the join table's own rows are not represented anywhere in the mapping IR handed to materialize_many/2",
       %{relationship: reference.relationship, metadata: reference.metadata}
     )}
  end

  defp resolve_reference_object(%ReferenceObjectMap{joins: joins} = reference, row, mapping_index, visible)
       when joins != [] do
    case Map.fetch(mapping_index, reference.parent_resource) do
      {:ok, parent_mapping} ->
        iri = resolve_composite_object_iri(joins, row, parent_mapping.subject_map)
        parent_subjects = Map.get(visible, reference.parent_resource, MapSet.new())

        if iri != nil and MapSet.member?(parent_subjects, iri), do: {:ok, iri}, else: {:ok, nil}

      :error ->
        {:ok, nil}
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

    with true <- String.contains?(template, placeholder),
         {:ok, lex} <- lexical(value) do
      String.replace(template, placeholder, percent_encode_iri_value(lex))
    else
      _ -> nil
    end
  end

  defp substitute_field(%SubjectMap{strategy: :column}, _field, value) do
    case lexical(value) do
      {:ok, lex} -> lex
      :error -> nil
    end
  end

  defp substitute_field(_subject_map, _field, _value), do: nil

  # The mapping's declared datatype wins: typed literals are what make numeric/temporal FILTERs and
  # ORDER BY semantically correct. Values with no declared datatype keep the plain-string form.
  # Returns `{:ok, literal}` or `:error` (value has no lexical form; never raises).
  # A column object map with `term_type: :iri` stores the whole IRI in the column (R2RML
  # `rr:column` + `rr:termType rr:IRI`): it is an IRI term, never a literal. A malformed stored
  # value is skipped (fail-closed, like `:column` subject maps), never literalized.
  defp object_term(value, %ObjectMap{term_type: :iri}) do
    with {:ok, lex} <- lexical(value),
         true <- valid_iri?(lex) do
      {:ok, RDF.iri(lex)}
    else
      _ -> :skip
    end
  end

  defp object_term(_value, %ObjectMap{term_type: :blank_node}), do: :unsupported

  defp object_term(value, object_map) do
    rdf_literal(value, object_map)
  end

  defp rdf_literal(value, object_map) do
    with {:ok, lex} <- lexical(value) do
      {:ok, build_literal(lex, object_map)}
    end
  end

  defp build_literal(lex, %ObjectMap{language: language}) when is_binary(language) and language != "",
    do: RDF.literal(lex, language: language)

  defp build_literal(lex, %ObjectMap{datatype: %{rdf_datatype: datatype}}) when is_binary(datatype) do
    if datatype == "http://www.w3.org/2001/XMLSchema#string" do
      RDF.literal(lex)
    else
      RDF.literal(lex, datatype: RDF.iri(datatype))
    end
  end

  defp build_literal(lex, _object_map), do: RDF.literal(lex)

  defp lexical(value) when is_binary(value), do: {:ok, value}
  defp lexical(%Decimal{coef: coef}) when coef in [:NaN, :inf], do: :error
  defp lexical(%Decimal{} = value), do: {:ok, Decimal.to_string(value, :normal)}
  defp lexical(%Date{} = value), do: {:ok, Date.to_iso8601(value)}
  defp lexical(%DateTime{} = value), do: {:ok, DateTime.to_iso8601(value)}
  defp lexical(%NaiveDateTime{} = value), do: {:ok, NaiveDateTime.to_iso8601(value)}
  defp lexical(%Time{} = value), do: {:ok, Time.to_iso8601(value)}
  defp lexical(value) when is_number(value) or is_atom(value), do: {:ok, to_string(value)}

  defp lexical(value) when is_struct(value) do
    if String.Chars.impl_for(value), do: {:ok, to_string(value)}, else: :error
  rescue
    _error in [ArgumentError, Protocol.UndefinedError] -> :error
  end

  defp lexical(_value), do: :error

  defp value_kind(%Decimal{}), do: "non-finite decimal"
  defp value_kind(value) when is_struct(value), do: inspect(value.__struct__)
  defp value_kind(value) when is_map(value), do: "map"
  defp value_kind(value) when is_tuple(value), do: "tuple"
  defp value_kind(value) when is_list(value), do: "list"
  defp value_kind(_value), do: "term"

  defp safe_atom(value) when is_atom(value), do: value

  defp safe_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
