# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer: AshSqlite (real file-backed WAL database).
#
# Implements the layer module contract (available?/0, setup/1, scenarios/0, canonical_digest/1).
# Reuses the resources/repo module of bench/support/sqlite_fixture.exs but starts the repo itself
# with a real pool, WAL journal mode and a busy timeout (the fixture's start!/0 pins pool_size 1).
#
# Scenarios: s1_healthy, s2_max_rows, s3_max_triples, s4_timeout, s5_memory, s6_recovery,
# s7_concurrent (32 readers + 4 writers + killer queries for opts[:seconds], default 30).
# A missing dependency is a loud skip, never a silent pass.

defmodule Bench.Layer.Sqlite do
  @moduledoc false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @fixture_path Path.expand("../../support/sqlite_fixture.exs", __DIR__)
  @fixture_repo Bench.SqliteFixture.Repo
  @fixture_dom Bench.SqliteFixture.Dom
  @fixture_person Bench.SqliteFixture.Person
  @fixture_org Bench.SqliteFixture.Org

  @pool_size 8
  @readers 32
  @writers 4
  @default_seconds 30
  @digest_rows 500
  @port_settle_ms 5_000

  @ex "https://ex.org/"
  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"

  @killers [
    {:max_rows, [max_rows: 10], :REFUSED_RESULT_LIMIT_EXCEEDED},
    {:max_triples, [max_triples: 10], :REFUSED_TRIPLE_LIMIT_EXCEEDED},
    {:timeout, [timeout_ms: 1], :REFUSED_QUERY_TIMEOUT},
    {:memory, [max_heap_words: 1_000], :REFUSED_MEMORY_LIMIT_EXCEEDED}
  ]

  @refusal_codes [
    :REFUSED_RESULT_LIMIT_EXCEEDED,
    :REFUSED_TRIPLE_LIMIT_EXCEEDED,
    :REFUSED_MEMORY_LIMIT_EXCEEDED,
    :REFUSED_QUERY_TIMEOUT
  ]

  # -- contract -------------------------------------------------------------------------------

  @spec available?() :: :ok | {:skip, String.t()}
  def available? do
    cond do
      not Code.ensure_loaded?(AshSqlite.DataLayer) ->
        {:skip, "AshSqlite.DataLayer not loadable (run with MIX_ENV=test where ash_sqlite is available)"}

      not Code.ensure_loaded?(Exqlite.Sqlite3) ->
        {:skip, "exqlite not loadable"}

      not File.regular?(@fixture_path) ->
        {:skip, "fixture missing: #{@fixture_path}"}

      true ->
        :ok
    end
  end

  @spec setup(keyword()) :: {:ok, map()} | {:skip, String.t()}
  def setup(opts) do
    with :ok <- available?() do
      do_setup(opts)
    end
  end

  defp do_setup(opts) do
    rows = Keyword.get(opts, :rows, 10_000)
    digest_rows = Keyword.get(opts, :digest_rows, @digest_rows)
    seconds = Keyword.get(opts, :seconds, @default_seconds)

    unless Code.ensure_loaded?(Bench.SqliteFixture), do: Code.require_file(@fixture_path)
    {:ok, _} = Application.ensure_all_started(:ash_sqlite)

    ports_before = length(:erlang.ports())

    path =
      Path.join(System.tmp_dir!(), "ash_r2rml_stress_sqlite_#{System.unique_integer([:positive])}.db")

    case @fixture_repo.start_link(
           database: path,
           pool_size: @pool_size,
           journal_mode: :wal,
           busy_timeout: 5_000
         ) do
      {:ok, pid} ->
        Process.unlink(pid)
        provision(pid, path, rows, digest_rows, seconds, ports_before)

      {:error, reason} ->
        cleanup_files(path)
        {:skip, "sqlite repo failed to start: #{inspect(reason, limit: 5)}"}
    end
  end

  defp provision(pid, path, rows, digest_rows, seconds, ports_before) do
    ctx_teardown = fn -> teardown(pid, path, ports_before) end

    try do
      ddl!()

      case journal_mode() do
        "wal" ->
          seed!(rows)
          spec = {@fixture_person, person_mapping()}

          {:ok,
           %{
             specs: [spec],
             domain: @fixture_dom,
             resource: @fixture_person,
             seed_rows: rows,
             digest_rows: digest_rows,
             seconds: seconds,
             sqlite_path: path,
             teardown: ctx_teardown
           }}

        other ->
          ctx_teardown.()
          {:skip, "WAL journal mode not active (journal_mode=#{inspect(other)})"}
      end
    rescue
      e ->
        _ = safe_teardown(ctx_teardown)
        {:skip, "sqlite provisioning failed: #{Exception.message(e)}"}
    end
  end

  defp safe_teardown(fun) do
    fun.()
  rescue
    e -> {:error, e}
  end

  @spec scenarios() :: [{atom(), String.t(), (map() -> :ok | {:fail, term()})}]
  def scenarios do
    [
      {:s1_healthy, "healthy shared query returns every seeded row, deterministically", &s1/1},
      {:s2_max_rows, "max_rows -> REFUSED_RESULT_LIMIT_EXCEEDED", &killer(&1, :max_rows)},
      {:s3_max_triples, "max_triples -> REFUSED_TRIPLE_LIMIT_EXCEEDED", &killer(&1, :max_triples)},
      {:s4_timeout, "timeout_ms 1 -> REFUSED_QUERY_TIMEOUT", &killer(&1, :timeout)},
      {:s5_memory, "max_heap_words -> REFUSED_MEMORY_LIMIT_EXCEEDED", &killer(&1, :memory)},
      {:s6_recovery, "killer storm leaves healthy digest unchanged and ports bounded", &s6/1},
      {:s7_concurrent, "32 readers + 4 writers + killers on WAL; 0 unhandled Exqlite.Error", &s7/1}
    ]
  end

  @spec canonical_digest(map()) :: binary()
  def canonical_digest(ctx) do
    limit = Map.get(ctx, :digest_rows, @digest_rows)
    sparql = String.replace_suffix(@sparql, " }", " . FILTER(?a <= #{limit}) }")
    {:ok, result} = AshR2RML.OBDA.query(ctx.specs, sparql, healthy_opts(ctx))
    Bench.Layer.Common.digest_of(result)
  end

  # -- scenarios ------------------------------------------------------------------------------

  defp s1(ctx) do
    with {:ok, result} <- healthy(ctx),
         :ok <- expect_count(result, ctx.seed_rows),
         d1 = digest_of(result.bindings, ctx.digest_rows),
         {:ok, again} <- healthy(ctx) do
      if digest_of(again.bindings, ctx.digest_rows) == d1,
        do: :ok,
        else: {:fail, :digest_not_deterministic}
    end
  end

  defp killer(ctx, id) do
    {^id, kopts, expected} = List.keyfind(@killers, id, 0)

    case AshR2RML.OBDA.query(ctx.specs, @sparql, killer_opts(ctx, kopts)) do
      {:error, err} ->
        case code_of(err) do
          ^expected -> after_killer_healthy(ctx)
          other -> {:fail, {:wrong_code, expected: expected, got: other}}
        end

      {:ok, _} ->
        {:fail, {:not_refused, expected}}
    end
  end

  defp after_killer_healthy(ctx) do
    with {:ok, result} <- healthy(ctx), do: expect_count(result, ctx.seed_rows)
  end

  defp s6(ctx) do
    before = canonical_digest(ctx)
    ports0 = length(:erlang.ports())

    storm =
      for _ <- 1..3, {id, _, _} <- @killers do
        killer(ctx, id)
      end

    with :ok <- first_fail(storm),
         true <- canonical_digest(ctx) == before or {:fail, :digest_changed_after_storm} do
      delta = length(:erlang.ports()) - ports0
      if delta <= 0, do: :ok, else: {:fail, {:port_growth, delta}}
    end
  end

  defp first_fail(results) do
    Enum.find(results, :ok, &(&1 != :ok))
  end

  defp s7(ctx) do
    seconds = Map.get(ctx, :seconds, @default_seconds)
    deadline = System.monotonic_time(:millisecond) + seconds * 1_000
    await_ms = seconds * 1_000 + 120_000

    readers = for id <- 0..(@readers - 1), do: Task.async(fn -> reader_loop(ctx, id, deadline, 0, new_counts()) end)
    writers = for id <- 0..(@writers - 1), do: Task.async(fn -> writer_loop(ctx, id, deadline, 0, new_counts()) end)

    r = readers |> Enum.map(&Task.await(&1, await_ms)) |> merge_counts()
    w = writers |> Enum.map(&Task.await(&1, await_ms)) |> merge_counts()

    IO.puts(
      "[sqlite s7] seconds=#{seconds} reader_ok=#{r.ok} reader_killer_refused=#{r.refused} " <>
        "reader_errors=#{r.errors} writer_ok=#{w.ok} writer_typed_errors=#{w.typed} " <>
        "unhandled=#{r.unhandled + w.unhandled}"
    )

    cond do
      r.unhandled + w.unhandled > 0 ->
        {:fail, {:unhandled, r.samples ++ w.samples}}

      r.errors > 0 ->
        {:fail, {:healthy_read_errors, r.errors, r.samples}}

      r.ok == 0 ->
        {:fail, :no_healthy_reads_completed}

      true ->
        after_killer_healthy(ctx)
    end
  end

  # -- S7 workers -----------------------------------------------------------------------------

  defp new_counts, do: %{ok: 0, refused: 0, errors: 0, typed: 0, unhandled: 0, samples: []}

  defp merge_counts(list) do
    Enum.reduce(list, new_counts(), fn c, acc ->
      %{
        ok: acc.ok + c.ok,
        refused: acc.refused + c.refused,
        errors: acc.errors + c.errors,
        typed: acc.typed + c.typed,
        unhandled: acc.unhandled + c.unhandled,
        samples: Enum.take(acc.samples ++ c.samples, 5)
      }
    end)
  end

  defp bump(c, key, sample \\ nil) do
    c = Map.update!(c, key, &(&1 + 1))
    if sample && length(c.samples) < 3, do: %{c | samples: [sample | c.samples]}, else: c
  end

  defp reader_loop(ctx, id, deadline, n, counts) do
    if System.monotonic_time(:millisecond) >= deadline do
      counts
    else
      counts =
        try do
          reader_op(ctx, id, n, counts)
        rescue
          e -> bump(counts, :unhandled, {:raised, e.__struct__, Exception.message(e)})
        catch
          kind, reason -> bump(counts, :unhandled, {kind, reason})
        end

      reader_loop(ctx, id, deadline, n + 1, counts)
    end
  end

  # Every 25th op a killer; reader 0 runs the full shared query every 20th op; otherwise a
  # constant-subject point lookup that must return exactly one binding.
  defp reader_op(ctx, id, n, counts) do
    cond do
      rem(n, 25) == 24 ->
        {kid, kopts, _expected} = Enum.at(@killers, rem(div(n, 25) + id, length(@killers)))

        case AshR2RML.OBDA.query(ctx.specs, @sparql, killer_opts(ctx, kopts)) do
          {:error, err} ->
            if code_of(err) in @refusal_codes,
              do: bump(counts, :refused),
              else: bump(counts, :unhandled, {:killer_untyped, kid, inspect(err, limit: 5)})

          {:ok, _} ->
            counts
        end

      id == 0 and rem(n, 20) == 19 ->
        case healthy(ctx) do
          {:ok, res} -> if length(res.bindings) == ctx.seed_rows, do: bump(counts, :ok), else: bump(counts, :errors, {:count, length(res.bindings)})
          {:fail, why} -> bump(counts, :errors, why)
        end

      true ->
        i = rem(n * 31 + id * 7, ctx.seed_rows) + 1
        iri = @ex <> "person/p#{i}"
        sparql = "SELECT ?n WHERE { <#{iri}> <https://schema.org/name> ?n }"

        case AshR2RML.OBDA.query(ctx.specs, sparql, healthy_opts(ctx)) do
          {:ok, %{bindings: [_one]}} -> bump(counts, :ok)
          other -> bump(counts, :errors, {:point, i, inspect(other, limit: 5)})
        end
    end
  end

  defp writer_loop(ctx, id, deadline, n, counts) do
    if System.monotonic_time(:millisecond) >= deadline do
      counts
    else
      counts =
        try do
          params = %{oid: "w#{id}-#{n}", title: "Writer #{id} #{n}"}

          case Ash.create(@fixture_org, params, action: :create, domain: ctx.domain) do
            {:ok, _} -> bump(counts, :ok)
            {:error, err} -> bump(counts, :typed, inspect(err, limit: 5))
          end
        rescue
          e -> bump(counts, :unhandled, {:raised, e.__struct__, Exception.message(e)})
        catch
          kind, reason -> bump(counts, :unhandled, {kind, reason})
        end

      writer_loop(ctx, id, deadline, n + 1, counts)
    end
  end

  # -- queries --------------------------------------------------------------------------------

  defp healthy_opts(ctx),
    do: [domain: ctx.domain, authorize?: false, allow_unauthorized: true, timeout_ms: 120_000]

  defp killer_opts(ctx, kopts), do: Keyword.merge(healthy_opts(ctx), kopts)

  defp healthy(ctx) do
    case AshR2RML.OBDA.query(ctx.specs, @sparql, healthy_opts(ctx)) do
      {:ok, result} -> {:ok, result}
      other -> {:fail, {:healthy_query_failed, inspect(other, limit: 8)}}
    end
  end

  defp expect_count(result, n) do
    case length(result.bindings) do
      ^n -> :ok
      got -> {:fail, {:row_count, expected: n, got: got}}
    end
  end

  defp code_of(err) do
    if Code.ensure_loaded?(Bench.Layer.Common) and function_exported?(Bench.Layer.Common, :code_of, 1) do
      apply(Bench.Layer.Common, :code_of, [err])
    else
      case err do
        %{code: c} -> c
        _ -> nil
      end
    end
  end

  # Layer-independent digest: bindings normalized to lexical strings, restricted to the first
  # `limit` persons by numeric pid, sorted.
  defp digest_of(bindings, limit) do
    bindings
    |> Enum.map(fn b -> {norm(b["s"]), norm(b["n"]), norm(b["a"])} end)
    |> Enum.filter(fn {s, _, _} -> pid_number(s) in 1..limit//1 end)
    |> Enum.sort_by(fn {s, _, _} -> pid_number(s) end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp pid_number(iri) do
    case Regex.run(~r{/person/p(\d+)$}, iri) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp norm(nil), do: ""
  defp norm(%RDF.IRI{} = i), do: to_string(i)
  defp norm(%RDF.Literal{} = l), do: RDF.Literal.lexical(l)
  defp norm(%{value: v}), do: norm(v)
  defp norm(v) when is_binary(v), do: v
  defp norm(v) when is_integer(v), do: Integer.to_string(v)
  defp norm(v), do: to_string(v)

  # -- provisioning ---------------------------------------------------------------------------

  defp ddl! do
    for sql <- [
          "CREATE TABLE IF NOT EXISTS bench_orgs (id TEXT PRIMARY KEY NOT NULL, oid TEXT, title TEXT)",
          "CREATE TABLE IF NOT EXISTS bench_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, " <>
            "age INTEGER, oid TEXT)"
        ] do
      Ecto.Adapters.SQL.query!(@fixture_repo, sql, [])
    end

    :ok
  end

  defp journal_mode do
    case Ecto.Adapters.SQL.query(@fixture_repo, "PRAGMA journal_mode=WAL", []) do
      {:ok, %{rows: [[mode]]}} -> String.downcase(to_string(mode))
      other -> other
    end
  end

  defp seed!(rows) do
    inputs = for i <- 1..rows, do: %{pid: "p#{i}", name: "Person #{i}", age: i}

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(inputs, @fixture_person, :create,
        domain: @fixture_dom,
        batch_size: 500,
        return_errors?: true
      )

    :ok
  end

  defp person_mapping do
    %Resource{
      ash_resource: @fixture_person,
      logical_table: %LogicalTable{table_name: "person"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "person/{pid}"},
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
          object_map: %ObjectMap{
            strategy: :column,
            value: "age",
            datatype: %Datatype{
              ash_type: :integer,
              rdf_datatype: "http://www.w3.org/2001/XMLSchema#integer"
            }
          }
        }
      ]
    }
  end

  # -- teardown -------------------------------------------------------------------------------

  defp teardown(pid, path, ports_before) do
    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      @port_settle_ms -> :ok
    end

    cleanup_files(path)

    deadline = System.monotonic_time(:millisecond) + @port_settle_ms
    delta = settle_ports(ports_before, deadline)

    if delta == 0 do
      :ok
    else
      msg = "[FAIL] sqlite: port_count delta #{delta} after teardown (before=#{ports_before})"
      IO.puts(msg)
      raise msg
    end
  end

  defp settle_ports(before, deadline) do
    delta = length(:erlang.ports()) - before

    if delta <= 0 or System.monotonic_time(:millisecond) >= deadline,
      do: max(delta, 0),
      else: settle_ports(before, deadline)
  end

  defp cleanup_files(path), do: for(suffix <- ["", "-shm", "-wal"], do: File.rm(path <> suffix))
end
