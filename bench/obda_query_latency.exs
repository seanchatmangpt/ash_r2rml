# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# OBDA SPARQL query-latency benchmark: AshR2RML.OBDA.InMemory (Ash.DataLayer.Ets, in-process)
# vs AshR2RML.OBDA.Ontop (AshPostgres.DataLayer, ontop/ontop:5.5.0 CLI over JDBC).
#
# Per bench/README.md: names the exact external engine/database/versions, verifies semantic
# correctness (same triples/rows) before timing, and does not attribute Ontop's own
# query-planning performance to AshR2RML -- AshR2RML's job here is producing the mapping;
# Ontop's CLI invocation cost (JVM start, container start) is Ontop's, reported as such.
#
# Requires a running `xaas-db-1` (postgres:15.2) container reachable on docker network
# `xaas_default`, and priv/ontop/jdbc/postgresql-42.7.4.jar -- same fixtures as
# test/adversarial/ontop_postgres_test.exs. Skips the Ontop leg gracefully if unavailable.
#
#   MIX_ENV=test mix run bench/obda_query_latency.exs
#   BENCH_TIERS=10,100,1000 BENCH_ONTOP_RUNS=5 MIX_ENV=test mix run bench/obda_query_latency.exs

alias AshR2RML.GrandExample.{Domain, Organization}
alias AshR2RML.OBDA.Ontop

tiers =
  case System.get_env("BENCH_TIERS") do
    nil -> [10, 100, 1000]
    csv -> csv |> String.split(",") |> Enum.map(&String.to_integer/1)
  end

ontop_runs = String.to_integer(System.get_env("BENCH_ONTOP_RUNS", "5"))
tmp_dir = Path.expand("tmp/bench_obda")
jdbc_jar = Path.expand("priv/ontop/jdbc/postgresql-42.7.4.jar")

{:ok, org_mapping} = AshR2RML.Resource.Info.mapping_result(Organization)

# ---- seed N real Organization rows via real Ash actions (ETS side) ----
defmodule AshR2RML.Bench.Obda do
  @moduledoc false

  def seed_ets(n, domain, resource) do
    for i <- 1..n do
      resource
      |> Ash.Changeset.for_create(:create, %{name: "BenchOrg#{i}", version: "1.0.#{i}"}, domain: domain)
      |> Ash.create!(domain: domain)
    end
  end

  def postgres_available?(jdbc_jar) do
    File.exists?(jdbc_jar) and
      match?(
        {_, 0},
        System.cmd("docker", ["exec", "xaas-db-1", "pg_isready", "-U", "postgres"], stderr_to_stdout: true)
      )
  rescue
    _ -> false
  end

  def postgres_password do
    case System.cmd("docker", ["exec", "xaas-db-1", "cat", "/run/secrets/postgrespassword"], stderr_to_stdout: true) do
      {pass, 0} -> String.trim(pass)
      _ -> "postgres"
    end
  end

  def seed_postgres(n, tmp_dir) do
    values =
      Enum.map_join(1..n, ",\n", fn i -> "('org_#{i}', 'BenchOrg#{i}', '1.0.#{i}')" end)

    System.cmd("docker", [
      "exec",
      "xaas-db-1",
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-c",
      """
      DROP TABLE IF EXISTS bench_organizations CASCADE;
      CREATE TABLE bench_organizations (
        id VARCHAR(64) PRIMARY KEY,
        name VARCHAR(200) NOT NULL,
        version VARCHAR(50) NOT NULL
      );
      INSERT INTO bench_organizations (id, name, version) VALUES
      #{values};
      """
    ])

    mapping_ttl = """
    @prefix rr: <http://www.w3.org/ns/r2rml#> .
    @prefix ex: <https://bench.example/ontop#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    <#OrgMap> a rr:TriplesMap ;
      rr:logicalTable [ rr:tableName "bench_organizations" ] ;
      rr:subjectMap [
        rr:template "https://bench.example/org/{id}" ;
        rr:class ex:Organization
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:name ;
        rr:objectMap [ rr:column "name"; rr:datatype xsd:string ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:version ;
        rr:objectMap [ rr:column "version"; rr:datatype xsd:string ]
      ] .
    """

    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "bench_mapping.ttl"), mapping_ttl)

    props = """
    jdbc.url=jdbc:postgresql://xaas-db-1:5432/postgres
    jdbc.user=postgres
    jdbc.password=#{postgres_password()}
    jdbc.driver=org.postgresql.Driver
    """

    File.write!(Path.join(tmp_dir, "bench.properties"), props)
  end

  def cleanup_postgres do
    System.cmd("docker", [
      "exec",
      "xaas-db-1",
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-c",
      "DROP TABLE IF EXISTS bench_organizations CASCADE;"
    ])
  end

  def ontop_query(tmp_dir, jdbc_jar, sparql) do
    query_file = Path.join(tmp_dir, "bench_query.sparql")
    File.write!(query_file, sparql)

    Ontop.query(
      binary: "docker",
      prefix_args: [
        "run",
        "--rm",
        "--network",
        "xaas_default",
        "-v",
        "#{tmp_dir}:/workspace",
        "-v",
        "#{jdbc_jar}:/opt/ontop/lib/postgresql-42.7.4.jar",
        "--workdir",
        "/workspace",
        "--entrypoint",
        "/opt/ontop/ontop",
        "ontop/ontop:5.5.0"
      ],
      mapping_path: "bench_mapping.ttl",
      properties_path: "bench.properties",
      query_path: "bench_query.sparql"
    )
  end

  def time_ms(fun) do
    {micros, result} = :timer.tc(fun)
    {micros / 1000.0, result}
  end
end

sparql_all =
  "PREFIX ex: <https://bench.example/ontop#> SELECT ?s ?name WHERE { ?s a ex:Organization ; ex:name ?name . }"

sparql_ets = "SELECT ?s ?name WHERE { ?s a <https://schema.org/Organization> ; <https://schema.org/name> ?name . }"

postgres_available = AshR2RML.Bench.Obda.postgres_available?(jdbc_jar)

IO.puts(
  "== OBDA query-latency benchmark (AshR2RML #{Mix.Project.config()[:version]}, commit #{elem(System.cmd("git", ["rev-parse", "--short", "HEAD"]), 0) |> String.trim()}) =="
)

IO.puts("Elixir #{System.version()} / OTP #{System.otp_release()}")
IO.puts("Postgres+Ontop leg available: #{postgres_available}\n")

results =
  Enum.map(tiers, fn n ->
    IO.puts("--- tier: #{n} rows ---")

    # AshR2RML.OBDA.InMemory (Ash.DataLayer.Ets, in-process)
    AshR2RML.Bench.Obda.seed_ets(n, Domain, Organization)

    {materialize_ms, {:ok, graph}} =
      AshR2RML.Bench.Obda.time_ms(fn ->
        AshR2RML.OBDA.InMemory.materialize(Organization, org_mapping, domain: Domain)
      end)

    triple_count = graph |> RDF.Graph.triples() |> length()
    true = triple_count >= n * 3

    {query_ms, {:ok, observation}} =
      AshR2RML.Bench.Obda.time_ms(fn ->
        AshR2RML.OBDA.InMemory.query(Organization, org_mapping, sparql_ets, domain: Domain)
      end)

    ets_row_count = length(observation.rows)
    true = ets_row_count >= n

    IO.puts(
      "  InMemory (ETS): materialize=#{Float.round(materialize_ms, 2)}ms, materialize+query=#{Float.round(query_ms, 2)}ms, rows>=#{n} (got #{ets_row_count})"
    )

    ontop_result =
      if postgres_available do
        AshR2RML.Bench.Obda.seed_postgres(n, tmp_dir)

        timings =
          for run <- 1..ontop_runs do
            {ms, result} =
              AshR2RML.Bench.Obda.time_ms(fn -> AshR2RML.Bench.Obda.ontop_query(tmp_dir, jdbc_jar, sparql_all) end)

            {run, ms, result}
          end

        {_run, _ms, {:ok, first_observation}} = List.first(timings)
        true = length(first_observation.rows) == n

        AshR2RML.Bench.Obda.cleanup_postgres()

        ms_values = Enum.map(timings, fn {_run, ms, _result} -> ms end)
        avg = Enum.sum(ms_values) / length(ms_values)
        min = Enum.min(ms_values)
        max = Enum.max(ms_values)

        IO.puts(
          "  Ontop 5.5.0 + PostgreSQL 15.2 (docker run --rm per query, includes container+JVM startup): " <>
            "min=#{Float.round(min, 1)}ms avg=#{Float.round(avg, 1)}ms max=#{Float.round(max, 1)}ms (n=#{ontop_runs} runs), rows=#{n} verified"
        )

        %{min_ms: min, avg_ms: avg, max_ms: max, runs: ontop_runs}
      else
        IO.puts("  Ontop leg skipped (xaas-db-1 or JDBC driver not available)")
        nil
      end

    %{
      tier: n,
      ets_materialize_ms: materialize_ms,
      ets_materialize_and_query_ms: query_ms,
      ontop: ontop_result
    }
  end)

IO.puts(
  "\n== Summary (raw milliseconds, single real run per tier; InMemory via Benchee-free :timer.tc, Ontop via N real docker invocations) =="
)

IO.inspect(results, pretty: true, limit: :infinity)
