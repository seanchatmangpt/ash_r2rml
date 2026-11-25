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
  `AshR2RML.OBDA.Worker.run/2`.

  ## Sources

  `resources_or_domain` is one of

    * an Ash domain module (its AshR2RML-extended resources are mapped via
      `AshR2RML.Resource.Info`),
    * a list of resource modules carrying the AshR2RML extension,
    * a list of `{ash_resource, %AshR2RML.Mapping.Resource{}}` specs (may be mixed with
      resource modules).

  ## Options

  `:actor`, `:tenant`, `:authorize?`, `:allow_sensitive?`, `:max_rows`, `:max_triples`,
  `:timeout_ms`; `:context`, `:domain`, `:allow_unauthorized`, `:require_authorizer`,
  `:require_tenant` are forwarded to the read. Exceeding `:max_triples` yields
  `:REFUSED_RESOURCE_BOUND`; `:max_rows` is enforced by the SPARQL engine.

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

  @forwarded [:actor, :tenant, :authorize?, :context, :domain] ++
               [:allow_unauthorized, :require_authorizer, :require_tenant, :max_rows, :max_triples]

  @event [:ash_r2rml, :obda, :query]

  @spec query(module() | [module() | InMemory.spec()], String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Error.t() | Refusal.t()}
  def query(resources_or_domain, sparql, opts \\ []) when is_binary(sparql) and is_list(opts) do
    started = System.monotonic_time()
    meta = %{sparql_bytes: byte_size(sparql)}

    :telemetry.execute(@event ++ [:start], %{system_time: System.system_time(), monotonic_time: started}, meta)

    try do
      result =
        case Worker.run(fn -> guarded_execute(resources_or_domain, sparql, opts, started) end, opts) do
          # Worker wraps the function's own {:ok, _} | {:error, _} return; flatten it.
          {:ok, inner} -> normalize_result(inner)
          {:error, _} = worker_error -> normalize_result(worker_error)
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
      details: %{kind: kind, class: class_of(reason), reason: inspect(reason, limit: 20, printable_limit: 500)}
    )
  end

  defp classify(%{__struct__: mod} = reason) do
    resource = resource_of(reason)

    cond do
      forbidden?(reason) -> {:REFUSED_UNAUTHORIZED, resource}
      mod == Ash.Error.Invalid.TenantRequired -> {:REFUSED_MISSING_TENANT, resource}
      true -> {:REFUSED_READ_FAILED, resource}
    end
  end

  defp classify(_reason), do: {:REFUSED_READ_FAILED, nil}

  defp forbidden?(%{__struct__: mod} = reason) do
    mod |> Module.split() |> Enum.member?("Forbidden") or
      (is_list(Map.get(reason, :errors)) and Enum.any?(reason.errors, &forbidden?/1))
  rescue
    _ -> false
  end

  defp forbidden?(_), do: false

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
  defp stop_meta(meta, _other), do: Map.put(meta, :result, :error)

  # Raises/throws/exits inside the worker become typed errors with the real exception struct
  # classified (Forbidden -> REFUSED_UNAUTHORIZED), instead of a generic worker crash.
  defp guarded_execute(source, sparql, opts, started) do
    execute(source, sparql, opts, started)
  rescue
    e -> {:error, wrap_failure(:error, e)}
  catch
    kind, reason -> {:error, wrap_failure(kind, reason)}
  end

  defp execute(source, sparql, opts, started) do
    with {:ok, specs} <- resolve_specs(source),
         {:ok, readable, pruned} <- preflight(specs, opts),
         {:ok, graph, ttl, observation} <- run_with_pushdown(readable, specs, sparql, opts) do
      {:ok, envelope(observation, graph, pruned, ttl, sparql, started)}
    end
  end

  # Root-resource pushdown (filter / sort / limit) when the query lowers safely; any refusal, any
  # failed post-read verification, or any unsure shape re-runs the unchanged full path.
  defp run_with_pushdown(readable, specs, sparql, opts) do
    case plan_pushdown(readable, sparql, opts) do
      nil ->
        run_pipeline(readable, specs, sparql, opts, nil)

      %Pushdown{} = pushdown ->
        with {:ok, graph, _ttl, observation} = ok <- run_pipeline(readable, specs, sparql, opts, pushdown),
             :ok <- QueryBuilder.verify(pushdown, graph, length(observation.rows)) do
          ok
        else
          _ -> run_pipeline(readable, specs, sparql, opts, nil)
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
    with {:ok, graph} <- InMemory.materialize_many(readable, materialize_opts(opts, specs, sparql, pushdown)),
         :ok <- check_max_triples(graph, readable, opts[:max_triples]),
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
      pre_opts = Keyword.take(opts, [:actor, :tenant, :domain])

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

  defp envelope(observation, graph, pruned, ttl, sparql, started) do
    rows = canonical_rows(observation, sparql)

    {bindings, triples} =
      case observation.result_kind do
        :rdf -> {[], rows}
        _ -> {rows, []}
      end

    stats = %{
      rows_read: graph |> RDF.Graph.subjects() |> Enum.count(),
      triples_emitted: RDF.Graph.triple_count(graph),
      duration_us: System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond),
      resources_pruned_by_policy: pruned
    }

    %Result{
      bindings: bindings,
      triples: triples,
      kind: observation.result_kind,
      stats: stats,
      digest: Result.digest(ttl, sparql, rows)
    }
  end

  # SPARQL.ex ignores ORDER BY / LIMIT / OFFSET, so they are applied here, after projection.
  defp canonical_rows(%{result_kind: :bindings, rows: rows}, sparql) do
    rows = if Regex.match?(~r/\bORDER\s+BY\b/i, sparql), do: rows, else: Result.canonical_sort(rows)
    Modifiers.run(rows, Modifiers.parse(sparql))
  end

  defp canonical_rows(%{rows: rows}, _sparql), do: Result.canonical_sort(rows)

  defp materialize_opts(opts, specs, sparql, pushdown) do
    base =
      opts
      |> Keyword.take(@forwarded)
      |> Keyword.put(:allow_sensitive, Keyword.get(opts, :allow_sensitive?, false))

    base =
      case pushdown do
        %Pushdown{} -> Keyword.put(base, :query_pushdown, Pushdown.read_option(pushdown))
        nil -> base
      end

    case {specs, constant_subject(sparql)} do
      {_, iri} when is_binary(iri) -> base |> Keyword.put(:subject_iri, iri) |> Keyword.put(:pushdown_ok, true)
      _ -> base
    end
  end

  defp local_opts(opts), do: opts |> Keyword.take([:max_rows]) |> Enum.reject(fn {_k, v} -> is_nil(v) end)

  defp check_max_triples(_graph, _specs, nil), do: :ok

  defp check_max_triples(graph, specs, max) when is_integer(max) and max > 0 do
    count = RDF.Graph.triple_count(graph)

    if count > max do
      {:error,
       Refusal.new(
         :REFUSED_RESOURCE_BOUND,
         specs |> List.first() |> elem(0),
         "materialized graph exceeds max_triples",
         %{
           max_triples: max,
           triples: count
         }
       )}
    else
      :ok
    end
  end

  @doc false
  @spec resolve_specs(term()) :: {:ok, [InMemory.spec()]} | {:error, Refusal.t()}
  def resolve_specs(domain) when is_atom(domain) and not is_nil(domain) do
    resolve_specs(AshR2RML.Resource.Info.domain_resources(domain))
  rescue
    _ -> {:error, refusal(domain, "not an Ash domain or mapped resource", %{})}
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
