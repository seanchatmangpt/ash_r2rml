# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress layer: mysql (AshMysql). Contract: available?/0, setup/1, scenarios/0, canonical_digest/1.
#
# ash_mysql is not a dependency of this repo. Every AshMysql reference is built at runtime
# (Module.concat + Code.compile_quoted), so this file compiles with or without the dep.
# Needs: Code.ensure_loaded?(AshMysql.DataLayer) and ASH_R2RML_MYSQL_URL
# (e.g. mysql://user:pass@127.0.0.1:3306/db). Otherwise {:skip, reason}; the driver maps
# {:skip, _} to a loud "[SKIP] mysql: ..." line and exit code 3.
#
# Scenario ids (assumed charter mapping):
#   s1 result limit, s2 triple limit, s3 query timeout, s4 heap limit,
#   s5 pool contention (pool_size 4, 64 concurrent callers, digest parity),
#   s12 mixed-case IRI / filter parity (constant-subject + FILTER are case-sensitive).

defmodule Bench.Layer.Mysql do
  @moduledoc false

  alias AshR2RML.Mapping.{LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @ex "https://ex.org/"
  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"
  @pool_size 4
  @callers 64
  @digest_rows 500

  @spec available?() :: :ok | {:skip, String.t()}
  def available? do
    cond do
      not Code.ensure_loaded?(data_layer()) ->
        {:skip, "ash_mysql not resolvable with Ash 3.x / not installed"}

      System.get_env("ASH_R2RML_MYSQL_URL") in [nil, ""] ->
        {:skip, "ASH_R2RML_MYSQL_URL not set"}

      true ->
        :ok
    end
  end

  @spec setup(keyword()) :: {:ok, map()} | {:skip, String.t()}
  def setup(opts) do
    case available?() do
      {:skip, _} = skip -> skip
      :ok -> do_setup(opts)
    end
  end

  defp do_setup(opts) do
    rows = Keyword.get(opts, :rows, 10_000)
    url = System.get_env("ASH_R2RML_MYSQL_URL")
    n = System.unique_integer([:positive])
    base = Module.concat([Bench.Layer.Mysql.Gen, "L#{n}"])
    repo = Module.concat(base, Repo)
    dom = Module.concat(base, Dom)
    res = Module.concat(base, Person)
    table = "bench_mysql_person_#{n}"

    compile!(base, repo, dom, res, table)
    {:ok, _} = Application.ensure_all_started(:ash_mysql)

    case repo.start_link(url: url, pool_size: @pool_size) do
      {:ok, pid} ->
        Process.unlink(pid)
        ddl!(repo, table)
        seed!(dom, res, rows)

        ctx = %{
          specs: [{res, mapping(res)}],
          domain: dom,
          resource: res,
          seed_rows: rows,
          digest_rows: min(Keyword.get(opts, :digest_rows, @digest_rows), rows),
          repo: repo,
          table: table,
          repo_pid: pid,
          teardown: fn -> teardown(repo, pid, table) end
        }

        {:ok, ctx}

      {:error, reason} ->
        {:skip, "mysql unreachable via ASH_R2RML_MYSQL_URL: #{inspect(reason)}"}
    end
  rescue
    e -> {:skip, "mysql setup failed: " <> Exception.message(e)}
  end

  @spec scenarios() :: [{atom(), String.t(), (map() -> :ok | {:fail, term()})}]
  def scenarios do
    [
      {:s1, "max_rows refuses oversized result", &s1/1},
      {:s2, "max_triples refuses oversized graph", &s2/1},
      {:s3, "timeout_ms refuses slow query", &s3/1},
      {:s4, "max_heap_words refuses heavy query", &s4/1},
      {:s5, "pool_size 4 under 64 concurrent callers stays correct", &s5/1},
      {:s12, "mixed-case IRI and filter parity", &s12/1}
    ]
  end

  @spec canonical_digest(map()) :: binary()
  def canonical_digest(ctx) do
    {:ok, result} = AshR2RML.OBDA.query(ctx.specs, digest_sparql(ctx), base_opts(ctx))
    digest(result)
  end

  # Same healthy query restricted to the first digest_rows rows (age == row index), so the
  # digest is identical across layers regardless of how many rows each layer seeded.
  defp digest_sparql(ctx) do
    String.replace_suffix(@sparql, " }", " . FILTER(?a <= #{ctx.digest_rows}) }")
  end

  # -- scenarios --------------------------------------------------------------------------

  defp s1(ctx),
    do: expect_refusal(ctx, "REFUSED_RESULT_LIMIT_EXCEEDED", max_rows: 10)

  defp s2(ctx),
    do: expect_refusal(ctx, "REFUSED_TRIPLE_LIMIT_EXCEEDED", max_triples: 10)

  defp s3(ctx),
    do: expect_refusal(ctx, "REFUSED_QUERY_TIMEOUT", timeout_ms: 1)

  defp s4(ctx),
    do: expect_refusal(ctx, "REFUSED_MEMORY_LIMIT_EXCEEDED", max_heap_words: 1_000)

  defp s5(ctx) do
    expected = canonical_digest(ctx)

    results =
      1..@callers
      |> Task.async_stream(
        fn _ -> AshR2RML.OBDA.query(ctx.specs, digest_sparql(ctx), base_opts(ctx)) end,
        max_concurrency: @callers,
        timeout: 60_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.to_list()

    bad =
      Enum.reject(results, fn
        {:ok, {:ok, r}} -> digest(r) == expected
        _ -> false
      end)

    if bad == [],
      do: :ok,
      else: {:fail, {:pool_contention, length(bad), Enum.take(bad, 2)}}
  end

  defp s12(ctx) do
    upper = point(ctx, @ex <> "person/P1")
    lower = point(ctx, @ex <> "person/p1")
    filt = filter_name(ctx, "person 1")
    exact = filter_name(ctx, "Person 1")

    cond do
      bindings(upper) != [] -> {:fail, {:case_insensitive_iri_match, bindings(upper)}}
      length(bindings(lower)) != 1 -> {:fail, {:lower_iri_lookup, lower}}
      bindings(filt) != [] -> {:fail, {:case_insensitive_filter_match, bindings(filt)}}
      length(bindings(exact)) != 1 -> {:fail, {:exact_filter_lookup, exact}}
      true -> :ok
    end
  end

  # -- helpers ----------------------------------------------------------------------------

  defp expect_refusal(ctx, want, extra) do
    case AshR2RML.OBDA.query(ctx.specs, @sparql, base_opts(ctx, extra)) do
      {:ok, _} ->
        {:fail, {:not_refused, want}}

      other ->
        got = Bench.Layer.Common.code_of(other)
        if to_string(got) == want, do: :ok, else: {:fail, {:wrong_code, want, got}}
    end
  end

  defp point(ctx, iri) do
    AshR2RML.OBDA.query(
      ctx.specs,
      "SELECT ?n WHERE { <#{iri}> <https://schema.org/name> ?n }",
      base_opts(ctx)
    )
  end

  defp filter_name(ctx, text) do
    AshR2RML.OBDA.query(
      ctx.specs,
      "SELECT ?s WHERE { ?s <https://schema.org/name> ?n . FILTER(?n = \"#{text}\") }",
      base_opts(ctx)
    )
  end

  defp bindings({:ok, %{bindings: b}}), do: b
  defp bindings(_), do: [:query_error]

  defp base_opts(ctx, extra \\ []),
    do: [domain: ctx.domain, authorize?: false, allow_unauthorized: true, timeout_ms: 60_000] ++ extra

  defp digest(%AshR2RML.OBDA.Result{} = result), do: Bench.Layer.Common.digest_of(result)

  defp data_layer, do: Module.concat(["AshMysql", "DataLayer"])
  defp repo_base, do: Module.concat(["AshMysql", "Repo"])

  defp compile!(_base, repo, dom, res, table) do
    dl = data_layer()
    rb = repo_base()

    quoted =
      quote do
        defmodule unquote(repo) do
          use unquote(rb), otp_app: :ash_r2rml
        end

        defmodule unquote(dom) do
          use Ash.Domain, validate_config_inclusion?: false

          resources do
            resource unquote(res)
          end
        end

        defmodule unquote(res) do
          use Ash.Resource, domain: unquote(dom), data_layer: unquote(dl)

          mysql do
            table unquote(table)
            repo unquote(repo)
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

    Code.compile_quoted(quoted)
    :ok
  end

  defp ddl!(repo, table) do
    sql =
      "CREATE TABLE #{table} (pid VARCHAR(64) NOT NULL PRIMARY KEY, name VARCHAR(255), age INT)"

    Ecto.Adapters.SQL.query!(repo, sql, [])
  end

  defp seed!(dom, res, rows) do
    inputs = for i <- 1..rows//1, do: %{pid: "p#{i}", name: "Person #{i}", age: i}

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(inputs, res, :create, domain: dom, batch_size: 500, return_errors?: true)

    :ok
  end

  defp teardown(repo, pid, table) do
    try do
      Ecto.Adapters.SQL.query(repo, "DROP TABLE IF EXISTS #{table}", [])
    catch
      _, _ -> :ok
    end

    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      5_000 -> :ok
    end
  end

  defp mapping(res) do
    %Resource{
      ash_resource: res,
      logical_table: %LogicalTable{table_name: "person"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "person/{pid}"},
      class_iris: [@ex <> "Person"],
      identities: [[:pid]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: "https://schema.org/name",
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %AshR2RML.Mapping.Datatype{
              ash_type: :string,
              rdf_datatype: "http://www.w3.org/2001/XMLSchema#string"
            }
          }
        },
        %PredicateObjectMap{
          attribute: :age,
          predicate_iri: "https://schema.org/age",
          object_map: %ObjectMap{
            strategy: :column,
            value: "age",
            datatype: %AshR2RML.Mapping.Datatype{
              ash_type: :integer,
              rdf_datatype: "http://www.w3.org/2001/XMLSchema#integer"
            }
          }
        }
      ]
    }
  end
end
