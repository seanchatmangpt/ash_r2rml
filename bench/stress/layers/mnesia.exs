# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer: Ash.DataLayer.Mnesia (real :mnesia, isolated temp dir, node-local ram tables).
#
# Contract (bench/stress/layers/*.exs): available?/0, setup/1, scenarios/0, canonical_digest/1.
#
#   S1  heap bomb          -> REFUSED_MEMORY_LIMIT_EXCEEDED
#   S2  row bound          -> REFUSED_RESULT_LIMIT_EXCEEDED
#   S3  triple bound       -> REFUSED_TRIPLE_LIMIT_EXCEEDED (REFUSED_RESOURCE_BOUND accepted: the
#                             code lib/ash_r2rml/obda.ex emitted at the time of writing)
#   S4  timeout            -> REFUSED_QUERY_TIMEOUT, process count back to baseline (bounded poll)
#   S5  storm              -> 8 killers (typed refusal each) + 8 healthy (identical digest each)
#   S10 mixed load         -> 32 OBDA readers + 4 Mnesia writers (incl. deliberate aborts):
#                             0 unhandled exits, aborts surface as typed errors, row count exact.
#
# teardown stops mnesia, deletes tables/schema/dir and RAISES when a table, the mnesia
# application, the temp dir or a process leaked.

defmodule Bench.Layer.Mnesia do
  @moduledoc false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @ex "https://ex.org/"
  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @xsd_int %AshR2RML.Mapping.Datatype{
    ash_type: :integer,
    rdf_datatype: "http://www.w3.org/2001/XMLSchema#integer"
  }
  @storm_ms 2_000
  @io_ms 60_000
  @proc_slack 3

  # -- contract ---------------------------------------------------------------------------

  def available? do
    cond do
      :code.which(:mnesia) == :non_existing -> {:skip, ":mnesia is not in the code path"}
      not Code.ensure_loaded?(Ash.DataLayer.Mnesia) -> {:skip, "Ash.DataLayer.Mnesia not loadable"}
      :mnesia.system_info(:is_running) in [:yes, :starting, :stopping] ->
        {:skip, "mnesia already running in this VM; refusing to clobber it"}
      true -> :ok
    end
  end

  def setup(opts) do
    case available?() do
      {:skip, _} = skip -> skip
      :ok -> do_setup(opts)
    end
  end

  def scenarios do
    [
      {:s1_heap_bomb, "blob rows under tiny max_heap_words refuse memory", &s1/1},
      {:s2_row_bound, "max_rows below row count refuses result limit", &s2/1},
      {:s3_triple_bound, "max_triples below graph size refuses triple limit", &s3/1},
      {:s4_timeout, "1 ms timeout refuses and process count returns to baseline", &s4/1},
      {:s5_storm, "killers refuse typed, healthy callers keep one digest", &s5/1},
      {:s10_mixed_load, "32 readers + 4 writers, aborts typed, no leaks", &s10/1}
    ]
  end

  def canonical_digest(ctx) do
    case AshR2RML.OBDA.query(ctx.digest_specs, @sparql, query_opts(ctx)) do
      {:ok, %{digest: digest}} when is_binary(digest) -> digest
      other -> raise "mnesia canonical_digest: query failed: #{inspect(other, limit: 20)}"
    end
  end

  # -- setup / teardown -------------------------------------------------------------------

  defp do_setup(opts) do
    rows = Keyword.get(opts, :rows, 10_000)
    digest_rows = Keyword.get(opts, :digest_rows, 500)
    baseline = length(Process.list())
    uid = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "ash_r2rml_bench_mnesia_#{uid}")
    prev_dir = Application.get_env(:mnesia, :dir)

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    Application.load(:mnesia)
    Application.put_env(:mnesia, :dir, String.to_charlist(dir))

    state = %{dir: dir, prev_dir: prev_dir, baseline: baseline}
    teardown = fn -> teardown(state) end

    try do
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()

      mods = define_modules(uid)
      tables = for {k, v} <- mods.tables, k != :blob, do: v

      for t <- tables, do: {:atomic, :ok} = create_table(t)
      :ok = :mnesia.wait_for_tables(tables, 10_000)

      seed(mods.person, mods.domain, rows, "p")
      seed(mods.digest, mods.domain, digest_rows, "p")

      ctx = %{
        specs: [{mods.person, person_mapping(mods.person, "person", "person")}],
        digest_specs: [{mods.digest, person_mapping(mods.digest, "person", "person")}],
        churn_specs: [{mods.churn, person_mapping(mods.churn, "churn", "churn")}],
        blob_specs: [{mods.blob, blob_mapping(mods.blob)}],
        domain: mods.domain,
        resource: mods.person,
        digest: mods.digest,
        churn: mods.churn,
        blob: mods.blob,
        tables: mods.tables,
        seed_rows: rows,
        digest_rows: digest_rows,
        baseline_procs: baseline,
        teardown: teardown
      }

      {:ok, ctx}
    rescue
      e ->
        teardown.()
        reraise e, __STACKTRACE__
    end
  end

  defp create_table(table),
    do: :mnesia.create_table(table, attributes: [:_pkey, :val], ram_copies: [node()])

  defp teardown(%{dir: dir, prev_dir: prev_dir, baseline: baseline}) do
    leaked_tables =
      if :mnesia.system_info(:is_running) == :yes do
        tables = :mnesia.system_info(:tables) -- [:schema]
        Enum.each(tables, &:mnesia.delete_table/1)
        :mnesia.system_info(:tables) -- [:schema]
      else
        []
      end

    :mnesia.stop()
    stopped? = poll(fn -> :mnesia.system_info(:is_running) == :no end, 5_000)
    :mnesia.delete_schema([node()])
    File.rm_rf(dir)

    if prev_dir,
      do: Application.put_env(:mnesia, :dir, prev_dir),
      else: Application.delete_env(:mnesia, :dir)

    procs_ok? = poll(fn -> length(Process.list()) <= baseline + @proc_slack end, 5_000)

    problems =
      [
        {leaked_tables != [], "leaked tables #{inspect(leaked_tables)}"},
        {not stopped?, "mnesia did not stop"},
        {File.exists?(dir), "temp dir #{dir} still present"},
        {not procs_ok?, "process count #{length(Process.list())} > baseline #{baseline}+#{@proc_slack}"}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    if problems != [], do: raise("mnesia layer teardown leak: " <> Enum.join(problems, "; "))
    :ok
  end

  # Bounded poll on an observable; the only wait in this file (POLL-STEP).
  defp poll(fun, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    do_poll(fun, deadline)
  end

  defp do_poll(fun, deadline) do
    cond do
      fun.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        # SLEEP-CLASS: POLL-STEP
        receive do
        after
          5 -> do_poll(fun, deadline)
        end
    end
  end

  # -- scenarios --------------------------------------------------------------------------

  defp s1(ctx) do
    table = ctx.tables.blob
    {:atomic, :ok} = create_table(table)
    :ok = :mnesia.wait_for_tables([table], 10_000)

    try do
      seed_blobs(ctx.blob, ctx.domain, 2_000)

      ctx.blob_specs
      |> AshR2RML.OBDA.query("SELECT ?s ?t WHERE { ?s <https://schema.org/text> ?t }",
        query_opts(ctx, max_heap_words: 50_000)
      )
      |> expect([:REFUSED_MEMORY_LIMIT_EXCEEDED], "s1")
    after
      :mnesia.delete_table(table)
    end
  end

  defp s2(ctx) do
    max = max(div(ctx.seed_rows, 2), 1)

    ctx.specs
    |> AshR2RML.OBDA.query(@sparql, query_opts(ctx, max_rows: max))
    |> expect([:REFUSED_RESULT_LIMIT_EXCEEDED], "s2")
  end

  defp s3(ctx) do
    ctx.specs
    |> AshR2RML.OBDA.query(@sparql, query_opts(ctx, max_triples: max(ctx.seed_rows, 1)))
    |> expect([:REFUSED_TRIPLE_LIMIT_EXCEEDED, :REFUSED_RESOURCE_BOUND], "s3")
  end

  defp s4(ctx) do
    baseline = length(Process.list())

    result =
      ctx.specs
      |> AshR2RML.OBDA.query(@sparql, query_opts(ctx, timeout_ms: 1))
      |> expect([:REFUSED_QUERY_TIMEOUT], "s4")

    case result do
      :ok ->
        if poll(fn -> length(Process.list()) <= baseline + @proc_slack end, 3_000),
          do: :ok,
          else: {:fail, "s4: process count #{length(Process.list())} did not return to #{baseline}"}

      fail ->
        fail
    end
  end

  defp s5(ctx) do
    expected = canonical_digest(ctx)
    deadline = System.monotonic_time(:millisecond) + @storm_ms
    {:ok, sup} = Task.Supervisor.start_link()

    try do
      killers = for k <- 0..7, do: Task.Supervisor.async_nolink(sup, fn -> killer_loop(ctx, k, deadline, []) end)
      healthy = for _ <- 1..8, do: Task.Supervisor.async_nolink(sup, fn -> healthy_loop(ctx, expected, deadline, []) end)

      failures =
        Enum.flat_map(collect(killers ++ healthy, @storm_ms + @io_ms), fn
          {:ok, fails} -> fails
          other -> [{:task_failed, other}]
        end)

      if failures == [], do: :ok, else: {:fail, {:s5, Enum.take(failures, 5)}}
    after
      Supervisor.stop(sup)
    end
  end

  defp killer_loop(ctx, k, deadline, fails) do
    if System.monotonic_time(:millisecond) >= deadline do
      fails
    else
      {opts, codes} = killer(k)

      fails =
        case AshR2RML.OBDA.query(ctx.digest_specs, @sparql, query_opts(ctx, opts)) do
          {:error, e} ->
            if Bench.Layer.Common.code_of(e) in codes,
              do: fails,
              else: [{:killer_wrong_code, k, Bench.Layer.Common.code_of(e)} | fails]

          other ->
            [{:killer_not_refused, k, summarize(other)} | fails]
        end

      killer_loop(ctx, k, deadline, fails)
    end
  end

  defp killer(k) do
    case rem(k, 4) do
      0 -> {[max_rows: 10], [:REFUSED_RESULT_LIMIT_EXCEEDED]}
      1 -> {[max_triples: 10], [:REFUSED_TRIPLE_LIMIT_EXCEEDED, :REFUSED_RESOURCE_BOUND]}
      2 -> {[max_heap_words: 5_000], [:REFUSED_MEMORY_LIMIT_EXCEEDED]}
      3 -> {[timeout_ms: 1], [:REFUSED_QUERY_TIMEOUT]}
    end
  end

  defp healthy_loop(ctx, expected, deadline, fails) do
    if System.monotonic_time(:millisecond) >= deadline do
      fails
    else
      fails =
        case AshR2RML.OBDA.query(ctx.digest_specs, @sparql, query_opts(ctx)) do
          {:ok, %{digest: ^expected, bindings: b}} when length(b) == ctx.digest_rows -> fails
          other -> [{:healthy_wrong, summarize(other)} | fails]
        end

      healthy_loop(ctx, expected, deadline, fails)
    end
  end

  defp s10(ctx) do
    deadline = System.monotonic_time(:millisecond) + @storm_ms
    specs = ctx.digest_specs ++ ctx.churn_specs
    {:ok, sup} = Task.Supervisor.start_link()

    try do
      readers =
        for _ <- 1..32 do
          Task.Supervisor.async_nolink(sup, fn -> reader_loop(ctx, specs, deadline, %{ok: 0, bad: []}) end)
        end

      writers =
        for w <- 1..4 do
          Task.Supervisor.async_nolink(sup, fn ->
            writer_loop(ctx, w, 0, deadline, %{written: 0, typed_aborts: 0, bad: []})
          end)
        end

      reader_res = collect(readers, @storm_ms + @io_ms)
      writer_res = collect(writers, @storm_ms + @io_ms)

      unhandled = for r <- reader_res ++ writer_res, not match?({:ok, _}, r), do: {:unhandled, r}
      bad = for {:ok, %{bad: b}} <- reader_res ++ writer_res, x <- b, do: x
      written = for({:ok, %{written: n}} <- writer_res, do: n) |> Enum.sum()
      aborts = for({:ok, %{typed_aborts: n}} <- writer_res, do: n) |> Enum.sum()
      size = :mnesia.table_info(ctx.tables.churn, :size)

      cond do
        unhandled != [] -> {:fail, {:s10_unhandled_exits, Enum.take(unhandled, 3)}}
        bad != [] -> {:fail, {:s10_bad_results, Enum.take(bad, 3)}}
        aborts == 0 -> {:fail, "s10: deliberate aborts did not surface as typed errors"}
        size != written -> {:fail, {:s10_row_count_mismatch, size: size, written: written}}
        true -> :ok
      end
    after
      Supervisor.stop(sup)
    end
  end

  defp reader_loop(ctx, specs, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      acc =
        try do
          case AshR2RML.OBDA.query(specs, @sparql, query_opts(ctx)) do
            {:ok, %{bindings: b}} when length(b) >= ctx.digest_rows -> %{acc | ok: acc.ok + 1}
            other -> %{acc | bad: [{:reader_wrong, summarize(other)} | acc.bad]}
          end
        catch
          :exit, reason -> %{acc | bad: [{:reader_exit, reason} | acc.bad]}
        end

      reader_loop(ctx, specs, deadline, acc)
    end
  end

  defp writer_loop(ctx, w, i, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      acc =
        if rem(i, 5) == 4 do
          case abort_tx(w, i) do
            {:error, {:mnesia_aborted, _}} -> %{acc | typed_aborts: acc.typed_aborts + 1}
            other -> %{acc | bad: [{:abort_untyped, other} | acc.bad]}
          end
        else
          case write_row(ctx, w, i) do
            :ok -> %{acc | written: acc.written + 1}
            other -> %{acc | bad: [{:write_failed, summarize(other)} | acc.bad]}
          end
        end

      writer_loop(ctx, w, i + 1, deadline, acc)
    end
  end

  # A real Mnesia transaction that aborts; the abort is wrapped as a typed error.
  defp abort_tx(w, i) do
    case :mnesia.transaction(fn -> :mnesia.abort({:bench_abort, w, i}) end) do
      {:aborted, reason} -> {:error, {:mnesia_aborted, reason}}
      {:atomic, v} -> {:ok, v}
    end
  catch
    :exit, reason -> {:exit, reason}
  end

  defp write_row(ctx, w, i) do
    attrs = %{pid: "w#{w}-#{i}", name: "Churn #{w}-#{i}", age: i}

    ctx.churn
    |> Ash.Changeset.for_create(:create, attrs, domain: ctx.domain, authorize?: false)
    |> Ash.create(domain: ctx.domain, authorize?: false)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  catch
    :exit, reason -> {:exit, reason}
  end

  # -- helpers ----------------------------------------------------------------------------

  defp collect(tasks, budget_ms) do
    tasks
    |> Task.yield_many(budget_ms)
    |> Enum.map(fn
      {_task, {:ok, value}} -> {:ok, value}
      {_task, {:exit, reason}} -> {:exit, reason}
      {task, nil} -> Task.shutdown(task, :brutal_kill) || {:timeout, :no_reply}
    end)
    |> Enum.map(fn
      {:ok, _} = ok -> ok
      {:exit, _} = exit -> exit
      other -> {:task_failed, other}
    end)
  end

  defp expect(result, codes, tag) do
    case result do
      {:error, e} ->
        code = Bench.Layer.Common.code_of(e)
        if code in codes, do: :ok, else: {:fail, "#{tag}: code #{inspect(code)} not in #{inspect(codes)}"}

      other ->
        {:fail, "#{tag}: expected refusal #{inspect(codes)}, got #{summarize(other)}"}
    end
  end

  defp summarize(term), do: inspect(term, limit: 8, printable_limit: 200)

  defp query_opts(ctx, extra \\ []),
    do: [domain: ctx.domain, authorize?: false, allow_unauthorized: true, timeout_ms: @io_ms] ++ extra

  defp seed(resource, domain, rows, prefix) do
    inputs = for i <- 1..rows, do: %{pid: "#{prefix}#{i}", name: "Person #{i}", age: i}
    bulk!(inputs, resource, domain)
  end

  defp seed_blobs(resource, domain, rows) do
    text = String.duplicate("x", 4_096)
    bulk!(for(i <- 1..rows, do: %{pid: "b#{i}", text: text <> Integer.to_string(i)}), resource, domain)
  end

  defp bulk!(inputs, resource, domain) do
    case Ash.bulk_create(inputs, resource, :create,
           domain: domain,
           batch_size: 500,
           authorize?: false,
           return_errors?: true
         ) do
      %Ash.BulkResult{status: :success} -> :ok
      other -> raise "mnesia seed failed for #{inspect(resource)}: #{inspect(other, limit: 10)}"
    end
  end

  defp person_mapping(resource, table_name, segment) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: table_name},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> segment <> "/{pid}"},
      class_iris: [@ex <> "Person"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: "https://schema.org/name",
          object_map: %ObjectMap{strategy: :column, value: "name"}
        },
        %PredicateObjectMap{
          attribute: :age,
          predicate_iri: "https://schema.org/age",
          object_map: %ObjectMap{strategy: :column, value: "age", datatype: @xsd_int}
        }
      ]
    }
  end

  defp blob_mapping(resource) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: "blob"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "blob/{pid}"},
      class_iris: [@ex <> "Blob"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :text,
          predicate_iri: "https://schema.org/text",
          object_map: %ObjectMap{strategy: :column, value: "text"}
        }
      ]
    }
  end

  # Per-setup unique resource modules and node-local table atoms.
  defp define_modules(uid) do
    root = Module.concat(Bench.Layer.Mnesia.Run, "R#{uid}")
    domain = Module.concat(root, Dom)
    loc = Macro.Env.location(__ENV__)

    names = [person: Person, digest: Digest, churn: Churn, blob: Blob]
    mods = Map.new(names, fn {k, n} -> {k, Module.concat(root, n)} end)
    tables = Map.new(names, fn {k, _} -> {k, :"bench_mnesia_#{k}_#{uid}"} end)

    Module.create(
      domain,
      quote do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(mods.person)
          resource unquote(mods.digest)
          resource unquote(mods.churn)
          resource unquote(mods.blob)
        end
      end,
      loc
    )

    for k <- [:person, :digest, :churn] do
      table = tables[k]

      Module.create(
        mods[k],
        quote do
          use Ash.Resource, domain: unquote(domain), data_layer: Ash.DataLayer.Mnesia

          mnesia do
            table unquote(table)
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
        end,
        loc
      )
    end

    blob_table = tables.blob

    Module.create(
      mods.blob,
      quote do
        use Ash.Resource, domain: unquote(domain), data_layer: Ash.DataLayer.Mnesia

        mnesia do
          table unquote(blob_table)
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:pid, :text]
          end
        end

        attributes do
          attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :text, :string, public?: true
        end
      end,
      loc
    )

    Map.merge(mods, %{domain: domain, tables: tables})
  end
end
