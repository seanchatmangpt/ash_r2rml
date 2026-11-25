# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Custom (in-repo, minimal) Ash.DataLayer stress layer. Implements the layer module contract:
# available?/0, setup/1, scenarios/0, canonical_digest/1. The data layer supports only :read and
# :limit (see bench/support/minimal_data_layer.exs), so filter/sort pushdown is impossible and
# every bound must hold on the full-read path.

Code.require_file(Path.expand("../../support/minimal_data_layer.exs", __DIR__))

defmodule Bench.Layer.Custom do
  @moduledoc false

  alias Bench.MinimalDataLayer, as: DL

  @resource Bench.MinimalDataLayer.Person
  @domain Bench.MinimalDataLayer.Domain

  @healthy "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @default_rows 10_000
  @default_digest_rows 500
  @settle_deadline_ms 2_000

  # -- contract ----------------------------------------------------------------

  def available? do
    if Code.ensure_loaded?(Ash.DataLayer) and Code.ensure_loaded?(AshR2RML.OBDA) and
         Code.ensure_loaded?(@resource) do
      :ok
    else
      {:skip, "Ash / AshR2RML.OBDA / Bench.MinimalDataLayer.Person not loadable"}
    end
  end

  def setup(opts) do
    rows = Keyword.get(opts, :rows, @default_rows)
    digest_rows = Keyword.get(opts, :digest_rows, @default_digest_rows)

    with :ok <- available?(),
         {:ok, mapping} <- AshR2RML.Resource.Info.mapping_result(@resource),
         {:ok, _pid} <- DL.start_store(@resource, people(rows)) do
      {:ok,
       %{
         specs: [{@resource, mapping}],
         domain: @domain,
         resource: @resource,
         seed_rows: rows,
         digest_rows: digest_rows,
         teardown: fn -> DL.stop_store(@resource) end
       }}
    else
      {:skip, _} = skip -> skip
      {:error, reason} -> {:skip, "custom layer setup failed: #{inspect(reason, limit: 5)}"}
    end
  end

  def scenarios do
    [
      {:s1_row_limit, "max_rows below row count refuses REFUSED_RESULT_LIMIT_EXCEEDED", &s1/1},
      {:s2_triple_limit, "max_triples below emitted count refuses REFUSED_TRIPLE_LIMIT_EXCEEDED", &s2/1},
      {:s3_timeout, "slow backend + timeout_ms refuses REFUSED_QUERY_TIMEOUT and leaks no processes", &s3/1},
      {:s4_memory, "tiny max_heap_words refuses REFUSED_MEMORY_LIMIT_EXCEEDED", &s4/1},
      {:s5_fault_wrap, "backend_unavailable faults wrap into typed errors and recover", &s5/1},
      {:s14_no_pushdown, "bounds and FILTER/LIMIT semantics hold when the layer cannot push down", &s14/1}
    ]
  end

  def canonical_digest(ctx) do
    # Digest is over exactly `digest_rows` rows: swap them in, query, restore.
    previous = DL.put_rows(ctx.resource, people(ctx.digest_rows))

    try do
      case AshR2RML.OBDA.query(ctx.specs, @healthy, [domain: ctx.domain, timeout_ms: 60_000] ++ actor_opts(ctx)) do
        {:ok, %{digest: digest}} when is_binary(digest) -> digest
        other -> raise "canonical_digest: healthy query failed: #{inspect(other, limit: 5)}"
      end
    after
      DL.restore_rows(ctx.resource, previous)
    end
  end

  # -- scenarios ---------------------------------------------------------------

  defp s1(ctx) do
    bound = max(1, div(ctx.seed_rows, 2))

    if ctx.seed_rows < 2 do
      {:fail, {:seed_too_small, ctx.seed_rows}}
    else
      expect_code(query(ctx, max_rows: bound, timeout_ms: 60_000), :REFUSED_RESULT_LIMIT_EXCEEDED)
    end
  end

  defp s2(ctx) do
    # Every row emits 3 triples (class, name, age); a bound of seed_rows is breached at ~1/3.
    expect_code(
      query(ctx, max_triples: max(1, ctx.seed_rows), timeout_ms: 60_000),
      :REFUSED_TRIPLE_LIMIT_EXCEEDED
    )
  end

  defp s3(ctx) do
    baseline = :erlang.system_info(:process_count)
    DL.configure(ctx.resource, slow_ms: 500)

    outcome =
      try do
        query(ctx, timeout_ms: 50)
      after
        DL.clear(ctx.resource)
      end

    with :ok <- expect_code(outcome, :REFUSED_QUERY_TIMEOUT) do
      case settle(baseline) do
        {true, _final, _ms} -> :ok
        {false, final, ms} -> {:fail, {:process_leak, baseline: baseline, final: final, waited_ms: ms}}
      end
    end
  end

  defp s4(ctx) do
    words = max(10_000, div(ctx.seed_rows, 2))
    expect_code(query(ctx, max_heap_words: words, timeout_ms: 60_000), :REFUSED_MEMORY_LIMIT_EXCEEDED)
  end

  defp s5(ctx) do
    # (a) every call faults: typed error, never a raise, never a healthy result.
    DL.configure(ctx.resource, fault_every: 1)

    always =
      try do
        query(ctx, timeout_ms: 60_000)
      after
        DL.clear(ctx.resource)
      end

    # (b) intermittent (every 3rd call): each outcome is ok or typed; both kinds occur.
    DL.configure(ctx.resource, fault_every: 3)

    outcomes =
      try do
        for _ <- 1..6, do: query(ctx, timeout_ms: 60_000)
      after
        DL.clear(ctx.resource)
      end

    # (c) recovery once faults stop.
    recovered = query(ctx, timeout_ms: 60_000)

    cond do
      match?({:ok, _}, always) ->
        {:fail, {:fault_ignored, :always_fault_returned_ok}}

      code_of(always) in [nil, :REFUSED_QUERY_TIMEOUT, :REFUSED_MEMORY_LIMIT_EXCEEDED] ->
        {:fail, {:untyped_or_wrong_fault_code, code_of(always)}}

      Enum.any?(outcomes, &(not match?({:ok, _}, &1) and code_of(&1) == nil)) ->
        {:fail, {:untyped_intermittent_error, outcomes |> Enum.reject(&match?({:ok, _}, &1)) |> inspect(limit: 5)}}

      not Enum.any?(outcomes, &match?({:ok, _}, &1)) or Enum.all?(outcomes, &match?({:ok, _}, &1)) ->
        {:fail, {:intermittent_not_mixed, Enum.map(outcomes, &tag/1)}}

      not match?({:ok, _}, recovered) ->
        {:fail, {:no_recovery, inspect(recovered, limit: 5)}}

      true ->
        :ok
    end
  end

  defp s14(ctx) do
    n = ctx.seed_rows

    cond do
      Ash.DataLayer.data_layer_can?(ctx.resource, :filter) ->
        {:fail, :layer_unexpectedly_supports_filter}

      n < 10 ->
        {:fail, {:seed_too_small, n}}

      true ->
        filtered =
          "SELECT ?s ?a WHERE { ?s <https://schema.org/age> ?a . FILTER(?a > #{n - 3}) }"

        limited = filtered <> " LIMIT 2"

        with {:ok, %{bindings: all}} <- query(ctx, sparql: filtered, timeout_ms: 60_000),
             :ok <- expect_count(all, 3, :filter_without_pushdown),
             {:ok, %{bindings: some}} <- query(ctx, sparql: limited, timeout_ms: 60_000),
             :ok <- expect_count(some, 2, :limit_without_pushdown) do
          # Row bound still enforced on the full-read fallback while a FILTER is present.
          expect_code(
            query(ctx, sparql: filtered, max_rows: max(1, div(n, 2)), timeout_ms: 60_000),
            :REFUSED_RESULT_LIMIT_EXCEEDED
          )
        else
          {:error, _} = error -> {:fail, {:query_failed, inspect(error, limit: 5)}}
          {:fail, _} = fail -> fail
        end
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp people(n) do
    for i <- 1..n//1, do: %{pid: "p#{i}", name: "Person #{i}", age: i}
  end

  defp actor_opts(ctx), do: Enum.reject([actor: Map.get(ctx, :actor), tenant: Map.get(ctx, :tenant)], &is_nil(elem(&1, 1)))

  defp query(ctx, opts) do
    {sparql, opts} = Keyword.pop(opts, :sparql, @healthy)
    AshR2RML.OBDA.query(ctx.specs, sparql, [domain: ctx.domain] ++ actor_opts(ctx) ++ opts)
  end

  defp expect_code(outcome, expected) do
    case code_of(outcome) do
      ^expected -> :ok
      other -> {:fail, {:expected, expected, got: other, outcome: inspect(outcome, limit: 5)}}
    end
  end

  defp expect_count(rows, n, label) do
    if length(rows) == n, do: :ok, else: {:fail, {label, expected: n, got: length(rows)}}
  end

  defp tag({:ok, _}), do: :ok
  defp tag(other), do: code_of(other)

  defp code_of(outcome) do
    if Code.ensure_loaded?(Bench.Layer.Common) and function_exported?(Bench.Layer.Common, :code_of, 1) do
      apply(Bench.Layer.Common, :code_of, [outcome])
    else
      case outcome do
        {:error, %{code: code}} -> code
        %{code: code} -> code
        _ -> nil
      end
    end
  end

  # Bounded deadline poll on the observable (process_count); no fixed sleep as synchronization.
  defp settle(baseline) do
    started = System.monotonic_time(:millisecond)
    poll(baseline, started, started + @settle_deadline_ms)
  end

  defp poll(baseline, started, deadline) do
    count = :erlang.system_info(:process_count)
    now = System.monotonic_time(:millisecond)

    cond do
      count <= baseline ->
        {true, count, now - started}

      now >= deadline ->
        {false, count, now - started}

      true ->
        # SLEEP-CLASS: POLL-STEP
        receive do
        after
          1 -> :ok
        end

        poll(baseline, started, deadline)
    end
  end
end
