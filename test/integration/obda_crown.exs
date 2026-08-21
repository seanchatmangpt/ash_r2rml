# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Real bounded crown: RDF/SHACL -> SemanticIR -> PostgreSQL + R2RML -> Ontop
# SPARQL, plus a Neo4j control observation over the same semantic fixture.

defmodule AshR2ml.ObdaCrown do
  @workspace "tmp/ash_r2ml_obda"
  @postgres_db "ash_r2ml"
  @postgres_user "postgres"
  @postgres_password "postgres"
  @neo4j_url "http://127.0.0.1:7474/db/neo4j/tx/commit"

  @profile """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix ex: <https://example.com/ontology/> .
  @prefix shapes: <https://example.com/shapes/> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2ml#> .

  shapes:OrganizationShape
      a sh:NodeShape ;
      sh:targetClass ex:Organization ;
      r2ml:ashModule "Obda.Organization" ;
      r2ml:tableName "organizations" ;
      r2ml:subjectTemplate "https://example.com/id/organization/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] .

  shapes:AccountShape
      a sh:NodeShape ;
      sh:targetClass ex:Account ;
      r2ml:ashModule "Obda.Account" ;
      r2ml:tableName "accounts" ;
      r2ml:subjectTemplate "https://example.com/id/account/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:organizationId ;
          r2ml:ashName "organization_id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:memberOf ;
          r2ml:ashName "organization" ;
          sh:class ex:Organization ;
          sh:minCount 1 ;
          sh:maxCount 1 ;
          r2ml:storageStrategy "foreign_key" ;
          r2ml:sourceKey "organization_id" ;
          r2ml:destinationKey "id"
      ] .
  """

  @sparql """
  PREFIX ex: <https://example.com/ontology/>
  SELECT ?account ?organization
  WHERE {
    ?account ex:memberOf ?organization .
  }
  ORDER BY ?account
  """

  @sql """
  SELECT
    'https://example.com/id/account/' || id AS account,
    'https://example.com/id/organization/' || organization_id AS organization
  FROM accounts
  ORDER BY account
  """

  @neo4j_query """
  MATCH (account:Account)-[:MEMBER_OF]->(organization:Organization)
  RETURN account.iri AS account, organization.iri AS organization
  ORDER BY account
  """

  def run! do
    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)

    {:ok, compilation} = AshR2ml.compile_turtle(@profile, ontology_hash: sha256(@profile))

    mapping_host = Path.expand(Path.join(@workspace, "mapping.ttl"))
    query_host = Path.expand(Path.join(@workspace, "query.rq"))
    properties_host = Path.expand(Path.join(@workspace, "postgres.properties"))

    File.write!(mapping_host, compilation.r2rml)
    File.write!(query_host, @sparql)

    File.write!(
      properties_host,
      """
      jdbc.url=jdbc:postgresql://127.0.0.1:5432/#{@postgres_db}
      jdbc.user=#{@postgres_user}
      jdbc.password=#{@postgres_password}
      jdbc.driver=org.postgresql.Driver
      """
    )

    reset_postgres!()
    psql_exec!(compilation.postgres_ddl)

    fixture_sql = """
    INSERT INTO organizations (id) VALUES ('org-1'), ('org-2');
    INSERT INTO accounts (id, organization_id) VALUES
      ('acct-1', 'org-1'),
      ('acct-2', 'org-1'),
      ('acct-3', 'org-2');
    """

    psql_exec!(fixture_sql)
    sql_rows = psql_query!(@sql)

    workspace = File.cwd!()
    container_root = "/workspace/" <> @workspace

    {:ok, sparql_observation} =
      AshR2ML.OBDA.Ontop.query(%{
        binary: "docker",
        prefix_args: [
          "run",
          "--rm",
          "--network",
          "host",
          "-e",
          "ONTOP_LOG_LEVEL=ERROR",
          "-v",
          "#{workspace}:/workspace:ro",
          "ontop/ontop:5.5.0",
          "ontop"
        ],
        mapping_path: container_root <> "/mapping.ttl",
        query_path: container_root <> "/query.rq",
        properties_path: container_root <> "/postgres.properties",
        mapping: compilation.r2rml,
        query: @sparql
      })

    unless sparql_observation.evidence_kind == :system_process do
      raise "OBDA crown requires a real system-process observation"
    end

    fixture_sha256 = sha256(fixture_sql)

    sparql_sql =
      AshR2ml.Parity.compare(
        :sparql_sql,
        :organization_account,
        sparql_observation.rows,
        sql_rows,
        %{
          left_system: :ontop,
          right_system: :postgres,
          left_query: @sparql,
          right_query: @sql,
          fixture_sha256: fixture_sha256,
          mapping_sha256: sparql_observation.mapping_sha256
        }
      )

    unless sparql_sql.verified?, do: raise("SPARQL/PostgreSQL parity mismatch")

    seed_neo4j!()
    neo4j_rows = neo4j_query!(@neo4j_query)

    neo4j_postgres =
      AshR2ml.Parity.compare(
        :neo4j_postgres,
        :organization_account,
        neo4j_rows,
        sql_rows,
        %{
          left_system: :neo4j,
          right_system: :postgres,
          left_query: @neo4j_query,
          right_query: @sql,
          fixture_sha256: fixture_sha256,
          mapping_sha256: sparql_observation.mapping_sha256
        }
      )

    unless neo4j_postgres.verified?, do: raise("Neo4j/PostgreSQL parity mismatch")

    technical_receipt =
      compilation.receipt
      |> AshR2ml.Compiler.attach_parity_witness(:sparql_sql, Map.from_struct(sparql_sql))
      |> AshR2ml.Compiler.attach_parity_witness(
        :neo4j_postgres,
        Map.from_struct(neo4j_postgres)
      )

    unless technical_receipt.query_parity == :VERIFIED,
      do: raise("SPARQL/SQL witness was not admitted")

    unless technical_receipt.neo4j_postgres_parity == :VERIFIED,
      do: raise("Neo4j/Postgres witness was not admitted")

    if AshR2ml.Compiler.cutover_ready?(technical_receipt),
      do: raise("technical parity must not manufacture cutover authority")

    File.write!(
      Path.join(@workspace, "parity-receipt.json"),
      Jason.encode!(
        json_term(%{
          status: :PARTIAL_ALIVE,
          standing: :bounded_real_obda_and_control_parity,
          sparql_sql: sparql_sql,
          neo4j_postgres: neo4j_postgres,
          compilation_receipt: technical_receipt
        }),
        pretty: true
      )
    )

    IO.puts("ALIVE bounded corpus: RDF/SHACL -> Postgres/R2RML -> Ontop and Neo4j/Postgres parity")
  end

  defp reset_postgres! do
    psql_exec!("DROP TABLE IF EXISTS accounts, organizations CASCADE;")
  end

  defp psql_exec!(sql) do
    {_output, 0} =
      System.cmd(
        "psql",
        [
          "--no-psqlrc",
          "-v",
          "ON_ERROR_STOP=1",
          "-h",
          "127.0.0.1",
          "-U",
          @postgres_user,
          "-d",
          @postgres_db,
          "-c",
          sql
        ],
        env: [{"PGPASSWORD", @postgres_password}],
        stderr_to_stdout: true
      )

    :ok
  end

  defp psql_query!(sql) do
    {output, 0} =
      System.cmd(
        "psql",
        [
          "--csv",
          "--no-psqlrc",
          "-P",
          "footer=off",
          "-h",
          "127.0.0.1",
          "-U",
          @postgres_user,
          "-d",
          @postgres_db,
          "-c",
          sql
        ],
        env: [{"PGPASSWORD", @postgres_password}]
      )

    AshR2ML.OBDA.Ontop.parse_csv(output)
  end

  defp seed_neo4j! do
    cypher!("MATCH (n) DETACH DELETE n")

    cypher!("""
    CREATE (o1:Organization {id: 'org-1', iri: 'https://example.com/id/organization/org-1'}),
           (o2:Organization {id: 'org-2', iri: 'https://example.com/id/organization/org-2'}),
           (a1:Account {id: 'acct-1', iri: 'https://example.com/id/account/acct-1'}),
           (a2:Account {id: 'acct-2', iri: 'https://example.com/id/account/acct-2'}),
           (a3:Account {id: 'acct-3', iri: 'https://example.com/id/account/acct-3'}),
           (a1)-[:MEMBER_OF]->(o1),
           (a2)-[:MEMBER_OF]->(o1),
           (a3)-[:MEMBER_OF]->(o2)
    """)
  end

  defp neo4j_query!(statement) do
    response = cypher!(statement)
    result = response["results"] |> List.first()
    columns = result["columns"]

    Enum.map(result["data"], fn %{"row" => row} ->
      Map.new(Enum.zip(columns, row))
    end)
  end

  defp cypher!(statement) do
    payload = Jason.encode!(%{statements: [%{statement: statement, resultDataContents: ["row"]}]})

    {output, 0} =
      System.cmd(
        "curl",
        [
          "--fail-with-body",
          "--silent",
          "--show-error",
          "-u",
          "neo4j:password",
          "-H",
          "Content-Type: application/json",
          "-d",
          payload,
          @neo4j_url
        ],
        stderr_to_stdout: true
      )

    decoded = Jason.decode!(output)

    case decoded["errors"] do
      [] -> decoded
      errors -> raise "Neo4j control query failed: #{inspect(errors)}"
    end
  end

  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()

  defp json_term(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_term(value)} end)
  end

  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&json_term/1)
  defp json_term(value) when value in [true, false, nil], do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value), do: value

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

AshR2ml.ObdaCrown.run!()
