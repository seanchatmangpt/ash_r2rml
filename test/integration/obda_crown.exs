# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Ash-first live OBDA crown. Run: `MIX_ENV=test mix run test/integration/obda_crown.exs`
# Requires the compose `xaas-db` Postgres (container xaas-db-1, network xaas_default) and
# the `ontop/ontop:5.5.0` image.
#
# One admitted subject (Ash resources Organization/Account) is observed through four routes:
#   1. AshR2RML.OBDA.InMemory over real Ash reads (Ash.DataLayer.Ets)
#   2. real Ontop CLI process over the generated R2RML and PostgreSQL
#   3. real Ontop SPARQL endpoint queried by AshR2RML.SPARQL.Protocol
#   4. plain SQL over PostgreSQL (the relational control)
# Technical parity never grants cutover authority.

defmodule AshR2RML.ObdaCrown.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.ObdaCrown.Organization
    resource AshR2RML.ObdaCrown.Account
  end
end

defmodule AshR2RML.ObdaCrown.Organization do
  use Ash.Resource,
    domain: AshR2RML.ObdaCrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:id, :name]
    end
  end

  r2rml do
    table_name("crown_organizations")
    class("https://example.com/ontology/Organization")

    subject do
      template("https://example.com/id/organization/{id}")
    end

    property(:name, "https://example.com/ontology/name")
  end
end

defmodule AshR2RML.ObdaCrown.Account do
  use Ash.Resource,
    domain: AshR2RML.ObdaCrown.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :organization, AshR2RML.ObdaCrown.Organization do
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
    table_name("crown_accounts")
    class("https://example.com/ontology/Account")

    subject do
      template("https://example.com/id/account/{id}")
    end

    reference(:organization, "https://example.com/ontology/memberOf")
  end
end

defmodule AshR2RML.ObdaCrown do
  alias AshR2RML.ObdaCrown.{Account, Domain, Organization}

  @workspace Path.expand("tmp/ash_r2rml_obda_crown")
  @jdbc_jar Path.expand("priv/ontop/jdbc/postgresql-42.7.4.jar")
  @ontop_image "ontop/ontop:5.5.0"
  @ontop_container "ash-r2ml-ontop-endpoint"
  @endpoint "http://127.0.0.1:8080/sparql"
  @network "xaas_default"
  @container "xaas-db-1"

  @sparql """
  PREFIX ex: <https://example.com/ontology/>
  SELECT ?account ?organization
  WHERE { ?account ex:memberOf ?organization . }
  ORDER BY ?account
  """

  @sql """
  SELECT 'https://example.com/id/account/' || id AS account,
         'https://example.com/id/organization/' || organization_id AS organization
  FROM crown_accounts ORDER BY account
  """

  @fixture_sql """
  DROP TABLE IF EXISTS crown_accounts, crown_organizations CASCADE;
  CREATE TABLE crown_organizations (id TEXT PRIMARY KEY, name TEXT NOT NULL);
  CREATE TABLE crown_accounts (id TEXT PRIMARY KEY, organization_id TEXT NOT NULL REFERENCES crown_organizations(id));
  INSERT INTO crown_organizations VALUES ('org-1', 'One'), ('org-2', 'Two');
  INSERT INTO crown_accounts VALUES ('acct-1', 'org-1'), ('acct-2', 'org-1'), ('acct-3', 'org-2');
  """

  def run! do
    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)

    {:ok, bundle} = AshR2RML.compile([Account])
    {:ok, r2rml} = AshR2RML.render(bundle)
    File.write!(Path.join(@workspace, "mapping.ttl"), r2rml)
    File.write!(Path.join(@workspace, "query.rq"), @sparql)

    File.write!(Path.join(@workspace, "postgres.properties"), """
    jdbc.url=jdbc:postgresql://#{@container}:5432/postgres
    jdbc.user=postgres
    jdbc.password=#{password()}
    jdbc.driver=org.postgresql.Driver
    """)

    psql!(@fixture_sql)
    sql_rows = psql_rows!(@sql)
    seed_ash!()

    fixture_sha = sha256(@fixture_sql)
    mapping_sha = sha256(r2rml)

    # Route 1: in-process, over real Ash reads.
    specs =
      for module <- [Organization, Account] do
        {module, AshR2RML.mapping(module)}
      end

    {:ok, in_memory} = AshR2RML.OBDA.InMemory.query_many(specs, @sparql, domain: Domain)
    assert_parity!(:in_memory, in_memory.rows, sql_rows, fixture_sha, mapping_sha)

    # Route 2: real Ontop CLI process.
    {:ok, cli} =
      AshR2RML.OBDA.Ontop.query(
        binary: "docker",
        prefix_args: docker_args() ++ ["--entrypoint", "/opt/ontop/ontop", @ontop_image],
        mapping_path: "mapping.ttl",
        query_path: "query.rq",
        properties_path: "postgres.properties",
        mapping: r2rml,
        query: @sparql
      )

    cli.evidence_kind == :system_process or raise "Ontop CLI observation is not a real process"
    assert_parity!(:ontop_cli, cli.rows, sql_rows, fixture_sha, mapping_sha)

    # Route 3: real Ontop SPARQL endpoint over HTTP.
    start_endpoint!()

    protocol =
      try do
        {:ok, obs} =
          AshR2RML.SPARQL.Protocol.query(@endpoint, @sparql,
            request_method: :get,
            protocol_version: "1.1",
            result_format: :json
          )

        obs
      after
        _ = System.cmd("docker", ["rm", "-f", @ontop_container], stderr_to_stdout: true)
      end

    protocol.evidence_kind == :sparql_protocol or raise "SPARQL protocol observation is not real"
    assert_parity!(:ontop_protocol, protocol.rows, sql_rows, fixture_sha, mapping_sha)

    protocol.result_sha256 == AshR2RML.SPARQL.Result.hash_rows(cli.rows) or
      raise "protocol and CLI normalized result identities differ"

    IO.puts("ALIVE bounded corpus (#{length(sql_rows)} rows): Ash InMemory + Ontop CLI + Ontop endpoint == PostgreSQL")
  end

  defp seed_ash! do
    for {id, name} <- [{"org-1", "One"}, {"org-2", "Two"}] do
      Organization |> Ash.Changeset.for_create(:create, %{id: id, name: name}) |> Ash.create!(domain: Domain)
    end

    for {id, org} <- [{"acct-1", "org-1"}, {"acct-2", "org-1"}, {"acct-3", "org-2"}] do
      Account |> Ash.Changeset.for_create(:create, %{id: id, organization_id: org}) |> Ash.create!(domain: Domain)
    end
  end

  defp assert_parity!(route, rows, sql_rows, fixture_sha, mapping_sha) do
    receipt =
      AshR2RML.Parity.compare(:sparql_sql, route, rows, sql_rows, %{
        left_system: route,
        right_system: :postgres,
        left_query: @sparql,
        right_query: @sql,
        fixture_sha256: fixture_sha,
        mapping_sha256: mapping_sha
      })

    receipt.verified? or raise "#{route}/PostgreSQL parity mismatch: #{inspect(receipt)}"
  end

  defp docker_args do
    [
      "run",
      "--rm",
      "--network",
      @network,
      "-v",
      "#{@workspace}:/workspace",
      "-v",
      "#{@jdbc_jar}:/opt/ontop/lib/postgresql-42.7.4.jar",
      "--workdir",
      "/workspace"
    ]
  end

  defp start_endpoint! do
    _ = System.cmd("docker", ["rm", "-f", @ontop_container], stderr_to_stdout: true)

    {_id, 0} =
      System.cmd(
        "docker",
        [
          "run",
          "-d",
          "--rm",
          "--name",
          @ontop_container,
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
          @ontop_image,
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

  # Single audited bounded poll: the endpoint's readiness is observed, never assumed.
  defp await_endpoint!(deadline) do
    case System.cmd("curl", ["--fail", "--silent", "http://127.0.0.1:8080/"], stderr_to_stdout: true) do
      {_out, 0} ->
        :ok

      _ ->
        System.monotonic_time(:millisecond) < deadline or raise "Ontop endpoint not ready before deadline"
        Process.sleep(500)
        await_endpoint!(deadline)
    end
  end

  defp password do
    System.get_env("POSTGRES_PASSWORD") || System.get_env("PGPASSWORD") || "postgres"
  end

  defp psql!(sql) do
    {_out, 0} =
      System.cmd(
        "docker",
        ["exec", @container, "psql", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres", "-c", sql],
        stderr_to_stdout: true
      )

    :ok
  end

  defp psql_rows!(sql) do
    {out, 0} =
      System.cmd("docker", [
        "exec",
        @container,
        "psql",
        "--csv",
        "-P",
        "footer=off",
        "-U",
        "postgres",
        "-d",
        "postgres",
        "-c",
        sql
      ])

    AshR2RML.OBDA.Ontop.parse_csv(out)
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

AshR2RML.ObdaCrown.run!()
