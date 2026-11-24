# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Ash-first Ontop 5.5.0 compliance crown. Run: `MIX_ENV=test mix run test/integration/ontop_compliance_crown.exs`
# Requires compose `xaas-db` (postgis, container xaas-db-1, network xaas_default) and `ontop/ontop:5.5.0`.
# Every protocol probe in AshR2RML.OBDA.Ontop.Compliance runs against a real Ontop endpoint whose
# mapping is compiled from Ash resources; all probes execute before the crown decides.

defmodule AshR2RML.ComplianceCrown.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.ComplianceCrown.Organization
    resource AshR2RML.ComplianceCrown.Account
    resource AshR2RML.ComplianceCrown.Place
  end
end

defmodule AshR2RML.ComplianceCrown.Organization do
  use Ash.Resource,
    domain: AshR2RML.ComplianceCrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:id]
    end
  end

  r2rml do
    table_name("compliance_organizations")
    class("https://example.com/ontology/Organization")

    subject do
      template("https://example.com/id/organization/{id}")
    end

    property(:id, "https://example.com/ontology/id")
  end
end

defmodule AshR2RML.ComplianceCrown.Account do
  use Ash.Resource,
    domain: AshR2RML.ComplianceCrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.ComplianceCrown.Organization do
      source_attribute :organization_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
      public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:id, :organization_id]
    end
  end

  r2rml do
    table_name("compliance_accounts")
    class("https://example.com/ontology/Account")

    subject do
      template("https://example.com/id/account/{id}")
    end

    property(:id, "https://example.com/ontology/id")
    property(:organization_id, "https://example.com/ontology/organizationId")
    reference(:organization, "https://example.com/ontology/memberOf")
  end
end

defmodule AshR2RML.ComplianceCrown.Place do
  use Ash.Resource,
    domain: AshR2RML.ComplianceCrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :geometry, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:id, :geometry]
    end
  end

  r2rml do
    sql_query("SELECT id, ST_AsText(geometry) AS geometry FROM compliance_places")
    class("https://example.com/ontology/Place")

    subject do
      template("https://example.com/id/place/{id}")
    end

    property(:id, "https://example.com/ontology/id")

    property(:geometry, "http://www.opengis.net/ont/geosparql#asWKT",
      datatype: "http://www.opengis.net/ont/geosparql#wktLiteral"
    )
  end
end

defmodule AshR2RML.ComplianceCrown do
  alias AshR2RML.ComplianceCrown.{Account, Organization, Place}
  alias AshR2RML.OBDA.Ontop.Compliance

  @workspace Path.expand("tmp/ash_r2rml_ontop_compliance")
  @jdbc_jar Path.expand("priv/ontop/jdbc/postgresql-42.7.4.jar")
  @container "ash-r2rml-ontop-compliance"
  @pg "xaas-db-1"
  @network "xaas_default"
  @image "ontop/ontop:5.5.0"
  @endpoint "http://127.0.0.1:8080/sparql"

  @ddl """
  CREATE EXTENSION IF NOT EXISTS postgis;
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  DROP TABLE IF EXISTS compliance_accounts, compliance_organizations, compliance_places CASCADE;
  CREATE TABLE compliance_organizations (id TEXT PRIMARY KEY);
  CREATE TABLE compliance_accounts (id TEXT PRIMARY KEY, organization_id TEXT NOT NULL REFERENCES compliance_organizations(id));
  CREATE TABLE compliance_places (id TEXT PRIMARY KEY, geometry geometry NOT NULL);
  INSERT INTO compliance_organizations VALUES ('org-1'), ('org-2');
  INSERT INTO compliance_accounts VALUES ('acct-1', 'org-1'), ('acct-2', 'org-1'), ('acct-3', 'org-2');
  INSERT INTO compliance_places VALUES ('p1', 'POINT(0 0)'), ('p2', 'POINT(1 1)');
  """

  def run! do
    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)

    {:ok, bundle} = AshR2RML.compile([Organization, Account, Place])
    {:ok, r2rml} = AshR2RML.render(bundle)
    File.write!(Path.join(@workspace, "mapping.ttl"), r2rml)

    File.write!(Path.join(@workspace, "postgres.properties"), """
    jdbc.url=jdbc:postgresql://#{@pg}:5432/postgres
    jdbc.user=postgres
    jdbc.password=#{System.get_env("POSTGRES_PASSWORD") || System.get_env("PGPASSWORD") || "postgres"}
    jdbc.driver=org.postgresql.Driver
    """)

    psql!(@ddl)
    start_endpoint!()

    results =
      try do
        Enum.map(Compliance.protocol_probes(), &execute_probe/1)
      after
        _ = System.cmd("docker", ["rm", "-f", @container], stderr_to_stdout: true)
      end

    failures = for {:error, failure} <- results, do: failure

    if failures != [] do
      raise "Ontop compliance crown: #{length(failures)}/#{length(results)} live protocol probes failed:\n" <>
              Enum.map_join(failures, "\n", &"  - #{&1.id}: #{&1.reason}")
    end

    receipt = %{
      status: :ALIVE,
      engine_version: Compliance.version(),
      mapping_sha256: :crypto.hash(:sha256, r2rml) |> Base.encode16(case: :lower),
      probe_count: length(results)
    }

    File.write!(Path.join(@workspace, "compliance-receipt.json"), inspect(receipt, pretty: true))
    IO.puts("ALIVE Ontop #{Compliance.version()} compliance crown: #{length(results)} live protocol probes")
  end

  defp execute_probe(probe) do
    case AshR2RML.SPARQL.Protocol.query(@endpoint, probe.query, request_method: :get, protocol_version: "1.1") do
      {:ok, %{evidence_kind: :sparql_protocol} = obs} ->
        {:ok, %{id: probe.id, result_sha256: obs.result_sha256, row_count: length(obs.rows)}}

      {:ok, _} ->
        {:error, %{id: probe.id, reason: "not a real SPARQL Protocol observation"}}

      {:error, reason} ->
        {:error, %{id: probe.id, reason: failure_reason(reason)}}
    end
  end

  defp failure_reason(%{request: %{http_status: _} = request}), do: failure_reason(request)

  defp failure_reason(%{http_status: status, http_response_body: body}) when is_binary(body) do
    "HTTP #{status}: " <> (body |> String.split("\n") |> Enum.take(3) |> Enum.join(" | ") |> String.slice(0, 400))
  end

  defp failure_reason(reason), do: reason |> inspect() |> String.slice(0, 400)

  defp start_endpoint! do
    _ = System.cmd("docker", ["rm", "-f", @container], stderr_to_stdout: true)

    {_id, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "-d",
          "--rm",
          "--name",
          @container,
          "-p",
          "8080:8080",
          "--network",
          @network,
          "-v",
          "#{@workspace}:/workspace",
          "-v",
          "#{@jdbc_jar}:/opt/ontop/lib/postgresql-42.7.4.jar",
          "--workdir",
          "/workspace",
          "--entrypoint",
          "/opt/ontop/ontop",
          @image,
          "endpoint",
          "-m",
          "mapping.ttl",
          "-p",
          "postgres.properties"
        ],
        stderr_to_stdout: true
      )

    await_endpoint!(System.monotonic_time(:millisecond) + 90_000)
  end

  # Single audited bounded poll: readiness is observed, never assumed.
  defp await_endpoint!(deadline) do
    case System.cmd("curl", ["--fail", "--silent", "--output", "/dev/null", "http://127.0.0.1:8080/"],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        :ok

      _ ->
        System.monotonic_time(:millisecond) < deadline or raise "Ontop endpoint not ready before deadline"
        Process.sleep(500)
        await_endpoint!(deadline)
    end
  end

  defp psql!(sql) do
    {out, status} =
      System.cmd(
        "docker",
        ["exec", @pg, "psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres", "-c", sql],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("psql failed: #{out}")
    :ok
  end
end

AshR2RML.ComplianceCrown.run!()
