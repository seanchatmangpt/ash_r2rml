# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer: AshCsv.DataLayer (real CSV file on disk). ash_csv is a :test-only dependency,
# so this layer reports a loud skip when it is not loaded. Layer module contract:
# available?/0, setup/1, scenarios/0, canonical_digest/1 (see bench/stress/README conventions).

if Code.ensure_loaded?(AshCsv.DataLayer) do
  defmodule Bench.Layer.Csv.Fixture.Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource Bench.Layer.Csv.Fixture.Person
      resource Bench.Layer.Csv.Fixture.DigestPerson
    end
  end

  defmodule Bench.Layer.Csv.Fixture.Person do
    @moduledoc false
    use Ash.Resource,
      domain: Bench.Layer.Csv.Fixture.Domain,
      data_layer: AshCsv.DataLayer,
      extensions: [AshR2RML]

    csv do
      file(Path.join(System.tmp_dir!(), "ash_r2rml_bench_csv_main_#{System.pid()}.csv"))
      create?(true)
      header?(true)
      columns([:pid, :name, :age])
    end

    r2rml do
      class_iri("https://ex.org/Person")
      subject_template("https://ex.org/person/{pid}")
      table_name("bench_people")

      attribute_mappings([
        {:name, "https://schema.org/name"},
        {:age, "https://schema.org/age"}
      ])
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:pid, :name, :age]
      end
    end

    attributes do
      attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
      attribute :age, :integer, public?: true
    end
  end

  defmodule Bench.Layer.Csv.Fixture.DigestPerson do
    @moduledoc false
    use Ash.Resource,
      domain: Bench.Layer.Csv.Fixture.Domain,
      data_layer: AshCsv.DataLayer,
      extensions: [AshR2RML]

    csv do
      file(Path.join(System.tmp_dir!(), "ash_r2rml_bench_csv_digest_#{System.pid()}.csv"))
      create?(true)
      header?(true)
      columns([:pid, :name, :age])
    end

    r2rml do
      class_iri("https://ex.org/Person")
      subject_template("https://ex.org/person/{pid}")
      table_name("bench_people")

      attribute_mappings([
        {:name, "https://schema.org/name"},
        {:age, "https://schema.org/age"}
      ])
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:pid, :name, :age]
      end
    end

    attributes do
      attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
      attribute :age, :integer, public?: true
    end
  end
end

defmodule Bench.Layer.Csv do
  @moduledoc false

  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @limited_sparql @sparql <> " LIMIT 50"
  @settle_deadline_ms 5_000
  @concurrency 64

  @domain Bench.Layer.Csv.Fixture.Domain
  @person Bench.Layer.Csv.Fixture.Person
  @digest_person Bench.Layer.Csv.Fixture.DigestPerson

  def available? do
    if Code.ensure_loaded?(AshCsv.DataLayer) and Code.ensure_loaded?(@person) do
      :ok
    else
      {:skip, "ash_csv not loaded (test-only dep; run with MIX_ENV=test)"}
    end
  end

  def setup(opts) do
    case available?() do
      :ok -> do_setup(opts)
      {:skip, _} = skip -> skip
    end
  end

  defp do_setup(opts) do
    rows = Keyword.get(opts, :rows, 10_000)
    digest_rows = Keyword.get(opts, :digest_rows, 500)

    main_path = AshCsv.DataLayer.Info.file(@person)
    digest_path = AshCsv.DataLayer.Info.file(@digest_person)

    write_csv!(main_path, rows)
    write_csv!(digest_path, digest_rows)

    with {:ok, main_mapping} <- AshR2RML.Resource.Info.mapping_result(@person),
         {:ok, digest_mapping} <- AshR2RML.Resource.Info.mapping_result(@digest_person) do
      {:ok,
       %{
         specs: [{@person, main_mapping}],
         digest_specs: [{@digest_person, digest_mapping}],
         domain: @domain,
         resource: @person,
         seed_rows: rows,
         digest_rows: digest_rows,
         teardown: fn ->
           File.rm(main_path)
           File.rm(digest_path)
           :ok
         end
       }}
    else
      {:error, reason} -> {:skip, "csv mapping refused: #{inspect(reason, limit: 5)}"}
    end
  end

  def scenarios do
    [
      {:s1_healthy, "healthy query returns every seeded row", &s1/1},
      {:s2_result_limit, "max_rows below row count refuses REFUSED_RESULT_LIMIT_EXCEEDED", &s2/1},
      {:s3_triple_limit, "max_triples below triple count refuses with a typed triple bound", &s3/1},
      {:s4_timeout, "timeout_ms killer refuses REFUSED_QUERY_TIMEOUT and reclaims processes", &s4/1},
      {:s5_heap, "max_heap_words killer refuses REFUSED_MEMORY_LIMIT_EXCEEDED", &s5/1},
      {:s13_concurrent, "64 concurrent callers incl. timeout/max_rows/heap killers; no fd/port leak",
       &s13/1}
    ]
  end

  def canonical_digest(ctx) do
    case AshR2RML.OBDA.query(ctx.digest_specs, @sparql,
           authorize?: false,
           domain: ctx.domain,
           max_rows: max(ctx.digest_rows * 2, 1_000),
           timeout_ms: 60_000
         ) do
      {:ok, %AshR2RML.OBDA.Result{} = result} -> Bench.Layer.Common.digest_of(result)
      other -> raise "csv canonical_digest failed: #{inspect(other, limit: 5)}"
    end
  end

  # -- scenarios --------------------------------------------------------------

  defp s1(ctx) do
    case query(ctx, @sparql, max_rows: ctx.seed_rows + 10, timeout_ms: 60_000) do
      {:ok, %{bindings: bindings}} when length(bindings) == ctx.seed_rows -> :ok
      {:ok, %{bindings: bindings}} -> {:fail, {:row_count, length(bindings), ctx.seed_rows}}
      other -> {:fail, {:unexpected, summarize(other)}}
    end
  end

  defp s2(ctx) do
    expect_code(query(ctx, @sparql, max_rows: 100, timeout_ms: 60_000), [:REFUSED_RESULT_LIMIT_EXCEEDED])
  end

  defp s3(ctx) do
    # OBDA's own post-materialization bound answers :REFUSED_RESOURCE_BOUND; the in-memory
    # materializer answers :REFUSED_TRIPLE_LIMIT_EXCEEDED. Both are typed fail-closed refusals.
    expect_code(
      query(ctx, @sparql, max_rows: ctx.seed_rows + 10, max_triples: 50, timeout_ms: 60_000),
      [:REFUSED_TRIPLE_LIMIT_EXCEEDED, :REFUSED_RESOURCE_BOUND]
    )
  end

  defp s4(ctx) do
    baseline = length(Process.list())

    with :ok <- expect_code(query(ctx, @sparql, timeout_ms: 1), [:REFUSED_QUERY_TIMEOUT]),
         :ok <- poll_until(fn -> length(Process.list()) <= baseline + 2 end) do
      :ok
    else
      :timeout -> {:fail, {:process_count_not_reclaimed, baseline, length(Process.list())}}
      {:fail, _} = fail -> fail
    end
  end

  defp s5(ctx) do
    expect_code(
      query(ctx, @sparql, max_rows: ctx.seed_rows + 10, max_heap_words: 10_000, timeout_ms: 60_000),
      [:REFUSED_MEMORY_LIMIT_EXCEEDED]
    )
  end

  defp s13(ctx) do
    # Warm up so lazily opened ports (code loading, telemetry) are not counted as a leak.
    case query(ctx, @limited_sparql, timeout_ms: 60_000) do
      {:ok, _} -> :ok
      other -> throw({:warmup_failed, summarize(other)})
    end

    ports_before = length(:erlang.ports())

    results =
      1..@concurrency
      |> Task.async_stream(
        fn i -> {kind_of(i), run_caller(ctx, kind_of(i))} end,
        max_concurrency: @concurrency,
        timeout: 120_000,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, r} -> r
        {:exit, reason} -> {:crash, {:exit, reason}}
      end)

    with :ok <- check_callers(results),
         :ok <- check_no_emfile(results),
         :ok <- check_ports(ports_before) do
      :ok
    end
  catch
    {:warmup_failed, why} -> {:fail, {:warmup_failed, why}}
  end

  defp kind_of(i) do
    case rem(i, 5) do
      0 -> :healthy
      1 -> :healthy
      2 -> :timeout
      3 -> :max_rows
      4 -> :heap
    end
  end

  defp run_caller(ctx, :healthy), do: query(ctx, @limited_sparql, timeout_ms: 60_000)
  defp run_caller(ctx, :timeout), do: query(ctx, @sparql, timeout_ms: 1)

  defp run_caller(ctx, :max_rows),
    do: query(ctx, @sparql, max_rows: 100, timeout_ms: 60_000)

  defp run_caller(ctx, :heap),
    do: query(ctx, @sparql, max_rows: ctx.seed_rows + 10, max_heap_words: 10_000, timeout_ms: 60_000)

  defp check_callers(results) do
    bad =
      Enum.reject(results, fn
        {:healthy, {:ok, _}} -> true
        {:timeout, r} -> code_of(r) == :REFUSED_QUERY_TIMEOUT
        {:max_rows, r} -> code_of(r) == :REFUSED_RESULT_LIMIT_EXCEEDED
        {:heap, r} -> code_of(r) == :REFUSED_MEMORY_LIMIT_EXCEEDED
        _ -> false
      end)

    case bad do
      [] -> :ok
      [{kind, r} | _] -> {:fail, {:caller_breach, kind, length(bad), summarize(r)}}
    end
  end

  defp check_no_emfile(results) do
    if Enum.any?(results, fn r -> inspect(r, limit: :infinity, printable_limit: :infinity) =~ "emfile" end),
      do: {:fail, :emfile_observed},
      else: :ok
  end

  defp check_ports(before) do
    case poll_until(fn -> length(:erlang.ports()) <= before end) do
      :ok -> :ok
      :timeout -> {:fail, {:port_leak, before, length(:erlang.ports())}}
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp query(ctx, sparql, opts) do
    AshR2RML.OBDA.query(ctx.specs, sparql, Keyword.merge([authorize?: false, domain: ctx.domain], opts))
  end

  defp expect_code(result, allowed) do
    code = code_of(result)

    if code in allowed,
      do: :ok,
      else: {:fail, {:expected_code, allowed, code, summarize(result)}}
  end

  defp code_of({:error, error}), do: code_of(error)
  defp code_of(%{code: code}), do: code
  defp code_of(_), do: nil

  defp summarize({:ok, %{stats: stats}}), do: {:ok, stats}
  defp summarize(other), do: inspect(other, limit: 5, printable_limit: 200)

  # Bounded poll on a real observable with a monotonic deadline; no fixed sleep as sync.
  defp poll_until(fun) do
    deadline = System.monotonic_time(:millisecond) + @settle_deadline_ms
    do_poll(fun, deadline)
  end

  defp do_poll(fun, deadline) do
    cond do
      fun.() -> :ok
      System.monotonic_time(:millisecond) >= deadline -> :timeout
      true ->
        :erlang.yield()
        do_poll(fun, deadline)
    end
  end

  defp write_csv!(path, rows) do
    File.mkdir_p!(Path.dirname(path))

    body =
      Stream.concat(
        ["pid,name,age\n"],
        Stream.map(1..rows//1, fn i -> "p#{i},Person #{i},#{i}\n" end)
      )

    File.write!(path, Enum.into(body, []))
  end
end
