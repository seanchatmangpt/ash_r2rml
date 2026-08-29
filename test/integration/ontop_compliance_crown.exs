# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OntopComplianceCrown do
  alias AshR2RML.OBDA.Ontop.Compliance

  @workspace "tmp/ash_r2rml_ontop_compliance"
  @container "ash-r2rml-ontop-compliance"
  @image "ontop/ontop:5.5.0"
  @endpoint "http://127.0.0.1:8080/sparql"
  @db "ash_r2rml"
  @user "postgres"
  @password "postgres"

  @profile """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix geo: <http://www.opengis.net/ont/geosparql#> .
  @prefix ex: <https://example.com/ontology/> .
  @prefix shapes: <https://example.com/shapes/> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2rml#> .

  shapes:OrganizationShape
      a sh:NodeShape ;
      sh:targetClass ex:Organization ;
      r2ml:ashModule "Compliance.Organization" ;
      r2ml:tableName "compliance_organizations" ;
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
      r2ml:ashModule "Compliance.Account" ;
      r2ml:tableName "compliance_accounts" ;
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

  shapes:PlaceShape
      a sh:NodeShape ;
      sh:targetClass ex:Place ;
      r2ml:ashModule "Compliance.Place" ;
      r2ml:tableName "compliance_places" ;
      r2ml:subjectTemplate "https://example.com/id/place/{id}" ;
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
          sh:path geo:asWKT ;
          r2ml:ashName "geometry" ;
          r2ml:ashType "AshGeo.Geometry" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype geo:wktLiteral ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] .
  """

  def run! do
    jdbc_directory = admitted_jdbc_directory!()

    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)

    {:ok, profile} = AshR2RML.ingest_turtle(@profile, ontology_hash: sha256(@profile))
    {:ok, compilation} = AshR2RML.Compiler.compile(profile)

    mapping = Path.expand(Path.join(@workspace, "mapping.ttl"))
    properties = Path.expand(Path.join(@workspace, "postgres.properties"))
    File.write!(mapping, compilation.r2rml)

    File.write!(
      properties,
      """
      jdbc.url=jdbc:postgresql://127.0.0.1:5432/#{@db}
      jdbc.user=#{@user}
      jdbc.password=#{@password}
      jdbc.driver=org.postgresql.Driver
      """
    )

    reset_fixture!(compilation.postgres_ddl)
    start_endpoint!(jdbc_directory)

    observations =
      try do
        Enum.map(Compliance.protocol_probes(), &execute_probe!/1)
      after
        stop_endpoint!()
      end

    receipt = %{
      status: :ALIVE,
      standing: :ontop_5_5_protocol_compliance_crown,
      engine: :ontop,
      engine_version: Compliance.version(),
      source: Compliance.source_identity(),
      mapping_sha256: sha256(compilation.r2rml),
      probe_count: length(observations),
      probes: observations,
      sparql_counts: Compliance.counts(:sparql_1_1),
      geosparql_counts: Compliance.counts(:geosparql_1_0)
    }

    File.write!(
      Path.join(@workspace, "compliance-receipt.json"),
      Jason.encode!(json_term(receipt), pretty: true)
    )

    IO.puts("ALIVE Ontop 5.5.0 compliance crown: #{length(observations)} live protocol probes")
  end

  defp execute_probe!(probe) do
    case AshR2RML.SPARQL.Protocol.query(
           @endpoint,
           probe.query,
           request_method: :get,
           protocol_version: "1.1"
         ) do
      {:ok, observation} ->
        unless observation.evidence_kind == :sparql_protocol do
          raise "probe #{probe.id} did not produce a real SPARQL Protocol observation"
        end

        %{
          id: probe.id,
          sections: probe.sections,
          query_sha256: observation.query_sha256,
          result_kind: observation.result_kind,
          result_sha256: observation.result_sha256,
          row_count: length(observation.rows)
        }

      {:error, reason} ->
        raise "Ontop compliance probe #{probe.id} failed: #{inspect(reason)}"
    end
  end

  defp reset_fixture!(ddl) do
    psql!("""
    CREATE EXTENSION IF NOT EXISTS postgis;
    DROP TABLE IF EXISTS compliance_accounts CASCADE;
    DROP TABLE IF EXISTS compliance_organizations CASCADE;
    DROP TABLE IF EXISTS compliance_places CASCADE;
    """)

    psql!(ddl)

    psql!("""
    INSERT INTO compliance_organizations (id) VALUES ('org-1'), ('org-2');
    INSERT INTO compliance_accounts (id, organization_id) VALUES
      ('acct-1', 'org-1'),
      ('acct-2', 'org-1'),
      ('acct-3', 'org-2');
    INSERT INTO compliance_places (id, geometry) VALUES
      ('p1', 'POINT(0 0)'),
      ('p2', 'POINT(1 1)');
    """)
  end

  defp psql!(sql) do
    {output, status} =
      System.cmd(
        "psql",
        ["-h", "127.0.0.1", "-U", @user, "-d", @db, "-v", "ON_ERROR_STOP=1", "-c", sql],
        env: [{"PGPASSWORD", @password}],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("psql failed: #{output}")
    output
  end

  defp start_endpoint!(jdbc_directory) do
    stop_endpoint!()

    workspace = File.cwd!()
    container_root = "/workspace/" <> @workspace

    {_output, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "-d",
          "--rm",
          "--name",
          @container,
          "--network",
          "host",
          "-e",
          "ONTOP_LOG_LEVEL=ERROR",
          "-v",
          "#{workspace}:/workspace:ro",
          "-v",
          "#{jdbc_directory}:/opt/ontop/jdbc:ro",
          @image,
          "ontop",
          "endpoint",
          "-m",
          container_root <> "/mapping.ttl",
          "-p",
          container_root <> "/postgres.properties"
        ],
        stderr_to_stdout: true
      )

    wait_for_endpoint!(60)
  end

  defp wait_for_endpoint!(0), do: raise("Ontop compliance endpoint did not become ready")

  defp wait_for_endpoint!(attempts) do
    case System.cmd(
           "curl",
           ["--fail", "--silent", "--output", "/dev/null", "http://127.0.0.1:8080/"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      _ ->
        Process.sleep(1_000)
        wait_for_endpoint!(attempts - 1)
    end
  end

  defp stop_endpoint! do
    System.cmd("docker", ["rm", "-f", @container], stderr_to_stdout: true)
    :ok
  end

  defp admitted_jdbc_directory! do
    directory =
      System.get_env("ASH_R2RML_ONTOP_JDBC_DIR") ||
        raise "ASH_R2RML_ONTOP_JDBC_DIR must point to the admitted Ontop JDBC directory"

    expected =
      System.get_env("ASH_R2RML_PGJDBC_SHA256") ||
        raise "ASH_R2RML_PGJDBC_SHA256 must pin the admitted PostgreSQL JDBC artifact"

    jar =
      directory
      |> Path.join("postgresql-*.jar")
      |> Path.wildcard()
      |> Enum.sort()
      |> case do
        [one] -> one
        jars -> raise "expected exactly one PostgreSQL JDBC jar, got #{inspect(jars)}"
      end

    actual = jar |> File.read!() |> sha256()

    unless actual == String.downcase(expected) do
      raise "PostgreSQL JDBC hash mismatch: expected #{expected}, got #{actual}"
    end

    directory
  end

  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()

  defp json_term(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_term(value)} end)
  end

  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp json_term(other), do: other

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

AshR2RML.OntopComplianceCrown.run!()
