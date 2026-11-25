# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA do
  @moduledoc """
  Public OBDA entry point: one SPARQL query over mapped Ash resources, returned as an
  `AshR2RML.OBDA.Result` envelope.

  Materialization and query execution are delegated to `AshR2RML.OBDA.InMemory` (real
  `Ash.read/2` under the caller's actor/tenant) and `AshR2RML.SPARQL.Local`; this module adds
  canonical ordering, bounds, a digest, stats and telemetry, and runs the work inside
  `AshR2RML.OBDA.Worker.call/2`.

  ## Sources

  `resources_or_domain` is one of

    * an Ash domain module (its AshR2RML-extended resources are mapped via
      `AshR2RML.Resource.Info`),
    * a list of resource modules carrying the AshR2RML extension,
    * a list of `{ash_resource, %AshR2RML.Mapping.Resource{}}` specs (may be mixed with
      resource modules).

  ## Options

  `:actor`, `:tenant`, `:authorize?`, `:allow_sensitive?` (alias `:allow_sensitive`),
  `:max_rows`, `:max_triples`, `:timeout_ms`, `:max_heap_words`; `:action` (read action name),
  `:context`, `:domain`, `:allow_unauthorized`, `:require_authorizer`, `:require_tenant` are
  forwarded to the read. Exceeding `:max_triples` yields `:REFUSED_TRIPLE_LIMIT_EXCEEDED`
  (raised by `AshR2RML.OBDA.InMemory`); `:max_rows` is enforced by the SPARQL engine. The four
  bounds must be positive integers, else `:REFUSED_UNSUPPORTED_SPARQL_FEATURE`.

  Resources on a `private?: true` ETS table are refused with `:REFUSED_PRIVATE_DATA_LAYER`:
  the read runs in a worker process that cannot see a private table.

  `:pushdown` (default `true`) enables root-resource pushdown of simple FILTERs, ORDER BY and
  LIMIT/OFFSET (see `AshR2RML.QueryBuilder.Lowering`); `pushdown: false` forces the full read.
  The narrowed read is handed to `AshR2RML.OBDA.InMemory` as the `:query_pushdown` read option
  (`%{resource:, mapping:, plan:}`); a receiver that ignores it simply reads everything.

  SPARQL.ex does not implement ORDER BY / LIMIT / OFFSET, so this module applies them to the
  projected rows (`AshR2RML.QueryBuilder.Modifiers`).

  ## Stats

    * `rows_read` -- distinct subjects materialized into the graph.
    * `triples_emitted` -- triples in the materialized graph.
    * `duration_us` -- wall time of the whole query.
    * `resources_pruned_by_policy` -- resources whose read the actor is not authorized for
      (`Ash.can?/3`); always 0 when `authorize?: false`.

  ## Telemetry

  `[:ash_r2rml, :obda, :query, :start | :stop | :exception]`. `:stop` metadata carries
  `result: :ok | :error` (and `code` for a refusal); `:exception` carries `kind`, `reason`,
  `stacktrace`. Durations are in native time units per telemetry convention.
  """

  alias AshR2RML.Error
  alias AshR2RML.Mapping.Bundle
  alias AshR2RML.OBDA.{InMemory, Result, Worker}
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.{Modifiers, Pushdown}
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Local

  @forwarded [:actor, :tenant, :authorize?, :context, :domain, :action] ++
               [:allow_unauthorized, :require_authorizer, :require_tenant, :max_rows, :max_triples]

  # An explicit `nil` bound means "use the default"; it is dropped before forwarding so a bound
  # can never be disabled (`Keyword.put_new`/`Keyword.get` defaults do not replace a present nil).
  @bound_forwarded [:max_rows, :max_triples]

  @event [:ash_r2rml, :obda, :query]

  @doc """
  Runs one SPARQL query over mapped Ash resources and returns `{:ok, %AshR2RML.OBDA.Result{}}`
  or `{:error, %AshR2RML.Error{} | %AshR2RML.Refusal{}}`.

  `resources_or_domain` and `opts` are described in the module documentation. A `nil` value for
  `:max_rows` or `:max_triples` selects the default bound (never "unbounded"); `:timeout_ms` and
  `:max_heap_words` must be positive integers or absent. On success the result carries
  canonically ordered `bindings` (SELECT/ASK) or `triples`/`quads` (CONSTRUCT/DESCRIBE), the
  result `kind`, `stats` and a content `digest`. Bound violations return typed refusals such as
  `:REFUSED_RESULT_LIMIT_EXCEEDED` and `:REFUSED_TRIPLE_LIMIT_EXCEEDED`.
  """
  @spec query(module() | [module() | InMemory.spec()], String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t() | Refusal.t()}
  def query(resources_or_domain, sparql, opts \\ []) when is_binary(sparql) and is_list(opts) do
    started = System.monotonic_time()
    meta = %{sparql_bytes: byte_size(sparql)}

    :telemetry.execute(@event ++ [:start], %{system_time: System.system_time(), monotonic_time: started}, meta)

    try do
      result =
        with :ok <- validate_bounds(opts),
             :ok <- check_private_data_layers(resources_or_domain) do
          case Worker.call(fn -> execute(resources_or_domain, sparql, opts, started) end, opts) do
            # Worker wraps the function's own {:ok, _} | {:error, _} return; flatten it.
            {:ok, inner} -> normalize_result(inner)
            {:error, _} = worker_error -> normalize_result(worker_error)
            # Raises/throws/exits inside the worker keep their real reason, so a Forbidden is
            # classified REFUSED_UNAUTHORIZED instead of a generic worker crash.
            {:raised, kind, reason, _stack} -> {:error, wrap_failure(kind, reason)}
          end
        else
          {:error, _} = refused -> normalize_result(refused)
        end

      :telemetry.execute(@event ++ [:stop], %{duration: System.monotonic_time() - started}, stop_meta(meta, result))
      result
    catch
      kind, reason ->
        :telemetry.execute(
          @event ++ [:exception],
          %{duration: System.monotonic_time() - started},
          Map.merge(meta, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
        )

        {:error, wrap_failure(kind, reason)}
    end
  end

  @doc false
  # Total error boundary: every non-ok outcome leaves `query/3` as `%Error{}` or `%Refusal{}`.
  @spec normalize_result(term()) :: {:ok, Result.t()} | {:error, Error.t() | Refusal.t()}
  def normalize_result({:ok, _} = ok), do: ok
  def normalize_result({:error, %Error{} = e}), do: {:error, e}
  def normalize_result({:error, %Refusal{} = r}), do: {:error, r}
  def normalize_result({:error, [%Refusal{} = r | _]}), do: {:error, r}
  def normalize_result({:error, other}), do: {:error, wrap_failure(:error, other)}
  def normalize_result(other), do: {:error, wrap_failure(:error, {:unexpected_result, other})}

  @doc false
  @spec wrap_failure(atom(), term()) :: Error.t()
  def wrap_failure(_kind, %Error{} = e), do: e
  def wrap_failure(_kind, %Refusal{} = r), do: Error.from_refusal(r)

  def wrap_failure(kind, reason) do
    {code, resource} = classify(reason)

    Error.new(code,
      resource: resource,
      message: nil,
      details: %{kind: kind, class: class_of(reason)}
    )
  end

  @doc false
  # Classifies a real Ash/Splode error, recursing into nested `.errors`, so Forbidden and
  # TenantRequired survive wrapping in `Ash.Error.Forbidden`/`Ash.Error.Invalid` classes.
  @spec classify(term()) :: {atom(), module() | nil}
  def classify(%{__struct__: _} = reason) do
    resource = resource_of(reason)

    cond do
      forbidden?(reason) -> {:REFUSED_UNAUTHORIZED, resource}
      tenant_required?(reason) -> {:REFUSED_MISSING_TENANT, resource}
      true -> {:REFUSED_READ_FAILED, resource}
    end
  end

  def classify(_reason), do: {:REFUSED_READ_FAILED, nil}

  defp forbidden?(%{__struct__: mod} = reason) do
    mod |> Module.split() |> Enum.member?("Forbidden") or nested?(reason, &forbidden?/1)
  rescue
    # Module.split/1 raises on a non-Elixir module name; that is simply "not a Forbidden".
    ArgumentError -> false
  end

  defp forbidden?(_), do: false

  defp tenant_required?(%{__struct__: mod} = reason),
    do: mod == Ash.Error.Invalid.TenantRequired or nested?(reason, &tenant_required?/1)

  defp tenant_required?(_), do: false

  defp nested?(reason, predicate) do
    case Map.get(reason, :errors) do
      errors when is_list(errors) -> Enum.any?(errors, predicate)
      _ -> false
    end
  end

  defp resource_of(reason) do
    case Map.get(reason, :resource) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _ -> nil
    end
  end

  defp class_of(%{__struct__: mod}), do: inspect(mod)
  defp class_of(_), do: nil

  defp stop_meta(meta, {:ok, _}), do: Map.put(meta, :result, :ok)
  defp stop_meta(meta, {:error, %Refusal{code: code}}), do: meta |> Map.put(:result, :error) |> Map.put(:code, code)
  defp stop_meta(meta, {:error, %Error{code: code}}), do: meta |> Map.put(:result, :error) |> Map.put(:code, code)

  @bound_keys [:max_rows, :max_triples, :timeout_ms, :max_heap_words]

  # Bounds must be positive integers (or absent/nil); anything else is refused up front rather than
  # reaching the worker or the engine with a nonsensical limit.
  defp validate_bounds(opts) do
    case Enum.find(@bound_keys, fn key ->
           value = Keyword.get(opts, key)
           not (is_nil(value) or (is_integer(value) and value > 0))
         end) do
      nil ->
        :ok

      key ->
        {:error,
         refusal("option #{key}", "#{key} must be a positive integer", %{
           option: key,
           value: inspect(Keyword.get(opts, key))
         })}
    end
  end

  # The read runs in a spawned worker; a `private?: true` ETS table belongs to the process that
  # created it, so the worker would silently read an empty table.
  defp check_private_data_layers(source) do
    with {:ok, specs} <- resolve_specs(source),
         [{resource, verdict} | _] <- non_confirmed_public(specs) do
      {:error,
       Error.new(:REFUSED_PRIVATE_DATA_LAYER,
         resource: resource,
         details: %{detail: private_detail(resource, verdict)}
       )}
    else
      _ -> :ok
    end
  end

  defp non_confirmed_public(specs) do
    for {resource, _} <- specs,
        verdict = private_ets(resource),
        verdict != false,
        do: {resource, verdict}
  end

  defp private_detail(resource, :private),
    do: "#{inspect(resource)} is backed by a private ETS table"

  defp private_detail(resource, :unknown),
    do: "#{inspect(resource)} data layer could not be introspected; refusing (fail closed)"

  # Fail closed: only a positively introspected non-private (or non-ETS) layer yields `false`.
  defp private_ets(resource) do
    cond do
      Ash.DataLayer.data_layer(resource) != Ash.DataLayer.Ets -> false
      not Code.ensure_loaded?(Ash.DataLayer.Ets.Info) -> :unknown
      not function_exported?(Ash.DataLayer.Ets.Info, :private?, 1) -> :unknown
      Ash.DataLayer.Ets.Info.private?(resource) == true -> :private
      Ash.DataLayer.Ets.Info.private?(resource) == false -> false
      true -> :unknown
    end
  rescue
    _e in [UndefinedFunctionError, ArgumentError, FunctionClauseError, KeyError] -> :unknown
  end

  defp execute(source, sparql, opts, started) do
    with :ok <- check_supported_shapes(sparql),
         :ok <- check_order_projected(sparql),
         :ok <- Modifiers.check(sparql),
         {:ok, specs} <- resolve_specs(source),
         {:ok, readable, pruned} <- preflight(specs, opts),
         {:ok, counts, ttl, observation, quad_graph} <- run_query(readable, specs, sparql, opts) do
      {:ok, envelope(observation, counts, pruned, ttl, sparql, started, quad_graph)}
    end
  end

  # GRAPH queries run against the materialized dataset (named graphs); everything else keeps the
  # union-graph pipeline with optional pushdown.
  defp run_query(readable, specs, sparql, opts) do
    case InMemory.GraphQuery.plan(sparql) do
      :none ->
        with {:ok, graph, ttl, observation} <- run_with_pushdown(readable, specs, sparql, opts) do
          counts = %{
            rows_read: graph |> RDF.Graph.subjects() |> Enum.count(),
            triples_emitted: RDF.Graph.triple_count(graph)
          }

          {:ok, counts, ttl, observation, nil}
        end

      {:ok, plan} ->
        run_dataset(readable, specs, sparql, opts, plan)

      {:error, message, evidence} ->
        {:error, refusal(:graph_pattern, message, evidence)}
    end
  end

  defp run_dataset(readable, specs, sparql, opts, plan) do
    {result, stats} = InMemory.query_with_stats(readable, sparql, materialize_opts(opts, sparql, nil))

    with {:ok, observation} <- result,
         {:ok, ttl} <- AshR2RML.R2RML.render(%Bundle{resources: Enum.map(specs, &elem(&1, 1))}) do
      quad_graph = if plan.kind == :iri, do: to_string(plan.iri)
      {:ok, Map.take(stats, [:rows_read, :triples_emitted]), ttl, observation, quad_graph}
    end
  end

  # The in-process engine silently ignores VALUES and sub-SELECTs and returns no rows for property
  # paths; a wrong answer is worse than a refusal, so those shapes are refused up front.
  @doc false
  @spec check_supported_shapes(String.t()) :: :ok | {:error, Refusal.t()}
  def check_supported_shapes(sparql) do
    plain = normalize_sparql(sparql)

    cond do
      Regex.match?(~r/\bVALUES\b/i, plain) -> unsupported_shape("VALUES")
      Regex.match?(~r/\{\s*SELECT\b/i, plain) -> unsupported_shape("sub-SELECT")
      property_path?(plain) -> unsupported_shape("property path")
      true -> :ok
    end
  end

  # Full-IRI (normalized to <>) and prefixed-name forms: sequence, alternative, inverse, and the
  # * + ? modifiers glued to a predicate. `?x+1` (no prefix) and `^^xsd:t` are not paths.
  @path_patterns [
    ~r/(<>|[\w-]*:[\w-]*)\s*[\/|]\s*(<>|[\w-]*:)/,
    ~r/(?<!\^)\^(?!\^)\s*(<>|[\w-]*:|\()/,
    ~r/(<>|[\w-]*:[\w-]+)[*+?](?=[\s)]|$)/,
    ~r/\(\s*(<>|[\w-]*:[\w-]*)\s*[\/|]/
  ]

  defp property_path?(plain), do: Enum.any?(@path_patterns, &Regex.match?(&1, plain))

  # Strings become "", IRIs become <>, comments are dropped, so keyword scans see only real tokens.
  defp normalize_sparql(sparql) do
    sparql
    |> String.replace(~r/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/s, "\"\"")
    |> String.replace(~r/<[^>\s]*>/, "<>")
    |> String.replace(~r/#[^\n]*/, "")
  end

  defp unsupported_shape(name) do
    {:error,
     refusal(:sparql, "#{name} is not supported by the in-process engine; refusing instead of answering wrongly", %{
       feature: name
     })}
  end

  # SPARQL.ex projects before this module sorts, so an ORDER BY variable that is not in the SELECT
  # list cannot be honored; it is refused loudly instead of being silently ignored.
  @doc false
  @spec check_order_projected(String.t()) :: :ok | {:error, Refusal.t()}
  def check_order_projected(sparql) do
    case Modifiers.parse(sparql) do
      {:ok, %{order: [_ | _] = order}} -> check_select_order(sparql, order)
      _ -> :ok
    end
  end

  @select_clause ~r/\bSELECT\b\s+(?:DISTINCT\s+|REDUCED\s+)?(.*?)\s*(?:\bWHERE\b|\{)/is
  @query_form ~r/\A (?:\s* (?:\#[^\n]*(?:\n|\z) | PREFIX\s+[^\s<]*\s*<[^>]*> | BASE\s+<[^>]*>))*
                  \s* (SELECT|ASK|CONSTRUCT|DESCRIBE)/xi

  defp check_select_order(sparql, order) do
    case Regex.run(@select_clause, normalize_sparql(sparql)) do
      [_, select] -> check_projected(select, order)
      nil -> unmatched_select(sparql)
    end
  end

  # A SELECT whose clause text cannot be matched must not fail open; other forms are untouched.
  defp unmatched_select(sparql) do
    case Regex.run(@query_form, sparql, capture: :all_but_first) do
      [form] ->
        if String.upcase(form) == "SELECT" do
          {:error,
           refusal(
             "ORDER BY",
             "SELECT clause could not be analyzed to verify ORDER BY variables are projected",
             %{query_form: "SELECT"}
           )}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp check_projected(select, order) do
    if Regex.match?(~r/\A\s*\*/, select) do
      :ok
    else
      projected = projected_variables(select)

      case for({var, _dir} <- order, var not in projected, do: var) do
        [] ->
          :ok

        missing ->
          {:error,
           refusal(
             "ORDER BY",
             "ORDER BY variable is not projected by the SELECT clause",
             %{unprojected: missing, projected: projected}
           )}
      end
    end
  end

  # Projected variables: bare `?v` entries and `(expr AS ?alias)` aliases. Variables that only
  # occur inside a parenthesized expression are not projected.
  @spec projected_variables(String.t()) :: [String.t()]
  defp projected_variables(select) do
    aliases = ~r/\bAS\s+[?$](\w+)\s*\)/i |> Regex.scan(select, capture: :all_but_first) |> List.flatten()
    bare = select |> strip_groups() |> then(&Regex.scan(~r/[?$](\w+)/, &1, capture: :all_but_first))
    Enum.uniq(List.flatten(bare) ++ aliases)
  end

  defp strip_groups(text) do
    case Regex.replace(~r/\([^()]*\)/, text, " ") do
      ^text -> text
      stripped -> strip_groups(stripped)
    end
  end

  # Root-resource pushdown (filter / sort / limit) when the query lowers safely; any refusal, any
  # failed post-read verification, or any unsure shape re-runs the unchanged full path.
  defp run_with_pushdown(readable, specs, sparql, opts) do
    case plan_pushdown(readable, sparql, opts) do
      nil ->
        run_pipeline(readable, specs, sparql, opts, nil)

      %Pushdown{} = pushdown ->
        # Refusals/errors from the pushed-down run are final (no second read); only a failed
        # post-read verification re-runs the unchanged full path.
        case run_pipeline(readable, specs, sparql, opts, pushdown) do
          {:ok, graph, _ttl, observation} = ok ->
            case QueryBuilder.verify(pushdown, graph, length(observation.rows)) do
              :ok -> ok
              _mismatch -> run_pipeline(readable, specs, sparql, opts, nil)
            end

          {:error, _} = error ->
            error
        end
    end
  end

  defp plan_pushdown(readable, sparql, opts) do
    if Keyword.get(opts, :pushdown, true) == true and is_nil(constant_subject(sparql)) do
      case QueryBuilder.lower(sparql, readable) do
        {:ok, %Pushdown{} = pushdown} -> pushdown
        :fallback -> nil
      end
    end
  end

  defp run_pipeline(readable, specs, sparql, opts, pushdown) do
    with {:ok, graph} <- InMemory.materialize_many(readable, materialize_opts(opts, sparql, pushdown)),
         {:ok, ttl} <- AshR2RML.R2RML.render(%Bundle{resources: Enum.map(specs, &elem(&1, 1))}),
         {:ok, observation} <- Local.query(graph, sparql, local_opts(opts)) do
      {:ok, graph, ttl, observation}
    end
  end

  # Per-resource policy/tenant preflight. Skipped entirely for `authorize?: false` so the
  # existing guard refusals of the read path keep their semantics. Pruned resources are
  # dropped from the read (zero rows) but still counted.
  defp preflight(specs, opts) do
    if Keyword.get(opts, :authorize?, true) == false do
      {:ok, specs, 0}
    else
      pre_opts = Keyword.take(opts, [:actor, :tenant, :context, :domain, :action])

      Enum.reduce_while(specs, {:ok, [], 0}, fn {resource, _mapping} = spec, {:ok, keep, pruned} ->
        case AshR2RML.OBDA.Preflight.check(resource, pre_opts) do
          :ok -> {:cont, {:ok, [spec | keep], pruned}}
          :pruned -> {:cont, {:ok, keep, pruned + 1}}
          {:error, _} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, keep, pruned} -> {:ok, Enum.reverse(keep), pruned}
        error -> error
      end
    end
  end

  # A constant subject IRI is pushed down only when the query is a single group whose
  # statements all belong to that one subject (a lone pattern, optionally `;`-chained) and
  # exactly one spec is queried. Anything else reads unnarrowed.
  @doc false
  @spec constant_subject(String.t()) :: String.t() | nil
  def constant_subject(sparql) do
    with [[_, body]] <- Regex.scan(~r/\bWHERE\s*\{([^{}]*)\}/is, sparql, capture: :all),
         1 <- sparql |> String.graphemes() |> Enum.count(&(&1 == "{")),
         [_, iri] <- Regex.run(~r/^\s*<([^>\s]+)>\s/, body),
         stripped = body |> String.replace(~r/<[^>\s]*>/, "<I>") |> String.replace(~r/"[^"]*"/, "\"S\""),
         false <- Regex.match?(~r/\b(UNION|OPTIONAL|MINUS|GRAPH|SERVICE|FILTER|BIND|VALUES)\b/i, stripped),
         true <- Regex.match?(~r/^\s*<I>[^.{}]*?\.?\s*$/s, stripped) do
      iri
    else
      _ -> nil
    end
  end

  defp envelope(observation, counts, pruned, ttl, sparql, started, quad_graph) do
    rows = canonical_rows(observation, sparql)

    {bindings, triples} =
      case observation.result_kind do
        :rdf -> {[], rows}
        _ -> {rows, []}
      end

    quads = Enum.map(triples, &Map.put_new(&1, "graph", quad_graph))

    stats = %{
      rows_read: counts.rows_read,
      triples_emitted: counts.triples_emitted,
      duration_us: System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond),
      resources_pruned_by_policy: pruned
    }

    %Result{
      bindings: bindings,
      triples: triples,
      quads: quads,
      kind: observation.result_kind,
      stats: stats,
      digest: Result.digest(ttl, sparql, rows)
    }
  end

  # SPARQL.ex ignores ORDER BY / LIMIT / OFFSET, so they are applied here, after projection
  # (ORDER BY variables outside the projection are refused up front by `check_order_projected/1`).
  defp canonical_rows(%{result_kind: :bindings, rows: rows}, sparql) do
    rows = if Regex.match?(~r/\bORDER\s+BY\b/i, sparql), do: rows, else: Result.canonical_sort(rows)
    Modifiers.run(rows, Modifiers.parse(sparql))
  end

  defp canonical_rows(%{rows: rows}, _sparql), do: Result.canonical_sort(rows)

  defp materialize_opts(opts, sparql, pushdown) do
    base =
      opts
      |> Keyword.take(@forwarded)
      |> Enum.reject(fn {key, value} -> key in @bound_forwarded and is_nil(value) end)
      |> Keyword.put(:allow_sensitive, allow_sensitive?(opts))

    base =
      case pushdown do
        %Pushdown{} -> Keyword.put(base, :query_pushdown, Pushdown.read_option(pushdown))
        nil -> base
      end

    case constant_subject(sparql) do
      iri when is_binary(iri) -> base |> Keyword.put(:subject_iri, iri) |> Keyword.put(:pushdown_ok, true)
      nil -> base
    end
  end

  # Both spellings are accepted; either set to `true` opts in.
  defp allow_sensitive?(opts),
    do: Keyword.get(opts, :allow_sensitive?, false) == true or Keyword.get(opts, :allow_sensitive, false) == true

  defp local_opts(opts), do: opts |> Keyword.take([:max_rows]) |> Enum.reject(fn {_k, v} -> is_nil(v) end)

  @doc false
  @spec resolve_specs(term()) :: {:ok, [InMemory.spec()]} | {:error, Refusal.t()}
  def resolve_specs(domain) when is_atom(domain) and not is_nil(domain) do
    resolve_specs(AshR2RML.Resource.Info.domain_resources(domain))
  rescue
    # A non-domain atom fails introspection with one of these; anything else is a real bug and crashes
    # into the `query/3` boundary instead of being relabelled.
    _e in [UndefinedFunctionError, ArgumentError, FunctionClauseError, KeyError, MatchError] ->
      {:error, refusal(domain, "not an Ash domain or mapped resource", %{})}
  end

  def resolve_specs([]), do: {:error, refusal(nil, "no mapped resources given", %{})}

  def resolve_specs(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case to_spec(item) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  def resolve_specs(other), do: {:error, refusal(other, "unsupported OBDA source", %{})}

  defp to_spec({resource, %AshR2RML.Mapping.Resource{} = mapping}) when is_atom(resource),
    do: {:ok, {resource, mapping}}

  defp to_spec(resource) when is_atom(resource) do
    case AshR2RML.Resource.Info.mapping_result(resource) do
      {:ok, mapping} -> {:ok, {resource, mapping}}
      {:error, %Refusal{}} = error -> error
    end
  end

  defp to_spec(other), do: {:error, refusal(other, "unsupported OBDA source entry", %{})}

  defp refusal(subject, detail, evidence),
    do: Refusal.new(:REFUSED_UNSUPPORTED_SPARQL_FEATURE, subject, detail, evidence)
end
