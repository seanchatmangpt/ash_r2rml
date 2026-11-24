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

  alias AshR2RML.Mapping.Bundle
  alias AshR2RML.OBDA.{InMemory, Result, Worker}
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Local

  @forwarded [:actor, :tenant, :authorize?, :context, :domain] ++
               [:allow_unauthorized, :require_authorizer, :require_tenant]

  @event [:ash_r2rml, :obda, :query]

  @spec query(module() | [module() | InMemory.spec()], String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, Refusal.t() | term()}
  def query(resources_or_domain, sparql, opts \\ []) when is_binary(sparql) and is_list(opts) do
    started = System.monotonic_time()
    meta = %{sparql_bytes: byte_size(sparql)}

    :telemetry.execute(@event ++ [:start], %{system_time: System.system_time(), monotonic_time: started}, meta)

    try do
      result =
        case Worker.run(fn -> execute(resources_or_domain, sparql, opts, started) end, opts) do
          # Worker wraps the function's own {:ok, _} | {:error, _} return; flatten it.
          {:ok, {:ok, _} = inner} -> inner
          {:ok, {:error, _} = inner} -> inner
          {:error, _} = worker_error -> worker_error
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

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp stop_meta(meta, {:ok, _}), do: Map.put(meta, :result, :ok)
  defp stop_meta(meta, {:error, %Refusal{code: code}}), do: meta |> Map.put(:result, :error) |> Map.put(:code, code)
  defp stop_meta(meta, _other), do: Map.put(meta, :result, :error)

  defp execute(source, sparql, opts, started) do
    with {:ok, specs} <- resolve_specs(source),
         {:ok, graph} <- InMemory.materialize_many(specs, materialize_opts(opts)),
         :ok <- check_max_triples(graph, specs, opts[:max_triples]),
         {:ok, ttl} <- AshR2RML.R2RML.render(%Bundle{resources: Enum.map(specs, &elem(&1, 1))}),
         {:ok, observation} <- Local.query(graph, sparql, local_opts(opts)) do
      {:ok, envelope(observation, graph, specs, ttl, sparql, opts, started)}
    end
  end

  defp envelope(observation, graph, specs, ttl, sparql, opts, started) do
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
      resources_pruned_by_policy: pruned_count(specs, opts)
    }

    %Result{
      bindings: bindings,
      triples: triples,
      kind: observation.result_kind,
      stats: stats,
      digest: Result.digest(ttl, sparql, rows)
    }
  end

  defp canonical_rows(%{result_kind: :bindings, rows: rows}, sparql) do
    if Regex.match?(~r/\bORDER\s+BY\b/i, sparql), do: rows, else: Result.canonical_sort(rows)
  end

  defp canonical_rows(%{rows: rows}, _sparql), do: Result.canonical_sort(rows)

  defp materialize_opts(opts) do
    opts
    |> Keyword.take(@forwarded)
    |> Keyword.put(:allow_sensitive, Keyword.get(opts, :allow_sensitive?, false))
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

  defp pruned_count(specs, opts) do
    if Keyword.get(opts, :authorize?, true) == false do
      0
    else
      Enum.count(specs, fn {resource, _mapping} -> not can_read?(resource, opts) end)
    end
  end

  defp can_read?(resource, opts) do
    action = Ash.Resource.Info.primary_action!(resource, :read).name
    can_opts = opts |> Keyword.take([:tenant, :domain]) |> Keyword.put(:maybe_is, true)
    Ash.can?({resource, action}, opts[:actor], can_opts) != false
  rescue
    _ -> true
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
