# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DataLayerContract do
  @moduledoc """
  One canonical resource pair compiled onto several Ash data layers so the same mapping law is
  exercised against each.

    * `Organization` -- composite natural key `{tenant_id, code}` (also the composite primary
      key), `:attribute` multitenancy on `tenant_id`, sensitive `internal_tax_id` (never mapped).
    * `Person` -- `belongs_to :organization`, built-in datatypes, `Ash.Policy.Authorizer` with a
      field policy on `:secret_note` (admin only), sensitive `ssn_token` (never mapped).

  `define/3` generates `<Name>.Domain`, `<Name>.Organization` and `<Name>.Person` on the layer
  `kind`:

    * `:ets` -- always available
    * `:sqlite` -- `AshSqlite.DataLayer` (only instantiate when `Code.ensure_loaded?/1` holds)
    * `:postgres` -- `AshPostgres.DataLayer` (tagged `:postgres`, excluded by default)

  The remaining functions are shared fixtures (seed data, canonical SPARQL, snapshots) used by
  `AshR2RML.DataLayerContract.Cases` and the cross-layer equivalence test.
  """

  alias AshR2RML.Mapping.{Datatype, ObjectMap, PredicateObjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal

  @ex "https://example.org/contract/"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  @preds %{
    org_code: @ex <> "orgCode",
    org_name: @ex <> "orgName",
    internal_tax_id: @ex <> "internalTaxId",
    name: @ex <> "name",
    age: @ex <> "age",
    active: @ex <> "active",
    score: @ex <> "score",
    born_on: @ex <> "bornOn",
    joined_at: @ex <> "joinedAt",
    secret_note: @ex <> "secretNote",
    ssn_token: @ex <> "ssnToken"
  }

  @orgs [
    {"t1", "acme/west #1", "Acme West", "TAX-ACME-WEST-0001"},
    {"t1", "plain", "Plain Org", "TAX-PLAIN-0002"},
    {"t2", "zeta", "Zeta Org", "TAX-ZETA-0003"}
  ]

  @people [
    {"00000000-0000-4000-8000-000000000001", "t1", "acme/west #1", "Ada", 36, true, 1.5, ~D[1990-05-01],
     ~U[2026-01-02 03:04:05Z], "NOTE-ADA-SECRET", "SSN-ADA-0001"},
    {"00000000-0000-4000-8000-000000000002", "t1", "plain", "Bob", 41, false, 2.25, ~D[1985-11-30],
     ~U[2026-02-03 04:05:06Z], "NOTE-BOB-SECRET", "SSN-BOB-0002"},
    {"00000000-0000-4000-8000-000000000003", "t2", "zeta", "Cy", 29, true, 3.0, ~D[1997-07-07],
     ~U[2026-03-04 05:06:07Z], "NOTE-CY-SECRET", "SSN-CY-0003"}
  ]

  @roles [:admin, :member, :outsider, nil]

  @doc "Predicate IRI for a contract attribute."
  @spec pred(atom()) :: String.t()
  def pred(key), do: Map.fetch!(@preds, key)

  @doc "Class IRI for `:org` or `:person`."
  @spec class_iri(:org | :person) :: String.t()
  def class_iri(:org), do: @ex <> "Organization"
  def class_iri(:person), do: @ex <> "Person"

  @doc "Subject IRI prefix for organizations."
  def org_subject_prefix, do: @ex <> "org/"

  @doc "Subject IRI prefix for people."
  def person_subject_prefix, do: @ex <> "person/"

  @doc "Seed organizations as `{tenant, code, name, internal_tax_id}`."
  def orgs, do: @orgs

  @doc "Seed people as `{id, tenant, org_code, name, age, active, score, born_on, joined_at, secret_note, ssn_token}`."
  def people, do: @people

  @doc "Tenants present in the seed data."
  def tenants, do: ["t1", "t2"]

  @doc "Actor roles exercised by the contract (`nil` is no actor)."
  def roles, do: @roles

  @doc "The actor value for a role; `:outsider` is a real actor holding no admitted role."
  def actor(nil), do: nil
  def actor(role) when is_atom(role), do: %{role: role}

  @doc "Resource module for `:org | :person` on layer `mod`."
  def resource(mod, :org), do: Module.concat(mod, Organization)
  def resource(mod, :person), do: Module.concat(mod, Person)

  @doc "Domain module of layer `mod`."
  def domain(mod), do: Module.concat(mod, Domain)

  # -- fixtures ---------------------------------------------------------------

  @doc "Destroys every row of both resources in every tenant."
  def clear!(mod) do
    domain = domain(mod)

    for kind <- [:person, :org], tenant <- tenants() do
      resource = resource(mod, kind)

      resource
      |> Ash.read!(tenant: tenant, domain: domain, authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, tenant: tenant, domain: domain, authorize?: false))
    end

    :ok
  end

  @doc "Inserts the seed rows. `order: :reverse` inserts them in reverse order."
  def seed!(mod, order \\ :forward) when order in [:forward, :reverse] do
    domain = domain(mod)
    orgs = if order == :reverse, do: Enum.reverse(@orgs), else: @orgs
    people = if order == :reverse, do: Enum.reverse(@people), else: @people

    for {tenant, code, name, tax} <- orgs do
      resource(mod, :org)
      |> Ash.Changeset.for_create(:create, %{code: code, name: name, internal_tax_id: tax},
        tenant: tenant,
        domain: domain
      )
      |> Ash.create!(tenant: tenant, domain: domain, authorize?: false)
    end

    for {id, tenant, org_code, name, age, active, score, born_on, joined_at, note, ssn} <- people do
      attrs = %{
        id: id,
        org_code: org_code,
        name: name,
        age: age,
        active: active,
        score: score,
        born_on: born_on,
        joined_at: joined_at,
        secret_note: note,
        ssn_token: ssn
      }

      resource(mod, :person)
      |> Ash.Changeset.for_create(:create, attrs, tenant: tenant, domain: domain)
      |> Ash.create!(tenant: tenant, domain: domain, authorize?: false)
    end

    :ok
  end

  # -- mappings and queries ---------------------------------------------------

  @doc "The DSL-derived mapping IR for `:org | :person`."
  def mapping(mod, kind), do: AshR2RML.Resource.Info.mapping!(resource(mod, kind))

  @doc "Adds a mapped scalar attribute to a mapping (used to prove sensitive refusal)."
  def with_attribute(%AshR2RML.Mapping.Resource{} = mapping, attribute, predicate_iri) do
    pom = %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: predicate_iri,
      object_map: %ObjectMap{
        strategy: :column,
        value: Atom.to_string(attribute),
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @xsd_string}
      }
    }

    %{mapping | predicate_object_maps: mapping.predicate_object_maps ++ [pom]}
  end

  @doc "Canonical organization SELECT."
  def org_sparql do
    "SELECT ?s ?code ?name WHERE { ?s a <#{class_iri(:org)}> ; <#{pred(:org_code)}> ?code ; " <>
      "<#{pred(:org_name)}> ?name }"
  end

  @doc "Canonical person SELECT over every non-policy-protected mapped attribute."
  def person_sparql do
    "SELECT ?s ?name ?age ?active ?score ?born ?joined WHERE { ?s a <#{class_iri(:person)}> ; " <>
      "<#{pred(:name)}> ?name ; <#{pred(:age)}> ?age ; <#{pred(:active)}> ?active ; " <>
      "<#{pred(:score)}> ?score ; <#{pred(:born_on)}> ?born ; <#{pred(:joined_at)}> ?joined }"
  end

  @doc "SELECT over the field-policy protected attribute."
  def secret_sparql, do: "SELECT ?s ?note WHERE { ?s <#{pred(:secret_note)}> ?note }"

  @doc "Runs `sparql` for `kind` through `AshR2RML.OBDA.InMemory` with the layer's domain."
  def run(mod, kind, sparql, opts \\ []) do
    InMemory.query(
      resource(mod, kind),
      Keyword.get_lazy(opts, :mapping, fn -> mapping(mod, kind) end),
      sparql,
      [domain: domain(mod)] ++ Keyword.delete(opts, :mapping)
    )
  end

  @doc """
  Canonical rows of a query result: sorted, every term normalized to its string form. A typed
  refusal discloses nothing, so it normalizes to `[]` (Ash may deny a read by filtering or by
  forbidding it; both mean no subject is published).
  """
  @spec visible({:ok, struct()} | {:error, Refusal.t()}) :: [map()]
  def visible({:ok, observation}) do
    observation.rows
    |> Enum.map(fn row -> Map.new(row, fn {k, v} -> {k, norm(v)} end) end)
    |> Enum.sort_by(&inspect/1)
  end

  def visible({:error, %Refusal{}}), do: []

  defp norm(value) when is_binary(value), do: value
  defp norm(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: inspect(value))

  @doc """
  Everything the layer publishes, keyed deterministically: organization rows per tenant and,
  per tenant and role, person rows and secret-note rows.
  """
  def snapshot(mod) do
    org =
      for tenant <- tenants(), into: %{} do
        {tenant, visible(run(mod, :org, org_sparql(), tenant: tenant))}
      end

    people =
      for tenant <- tenants(), role <- @roles, into: %{} do
        opts = [tenant: tenant, actor: actor(role)]

        {{tenant, role},
         %{
           people: visible(run(mod, :person, person_sparql(), opts)),
           secrets: visible(run(mod, :person, secret_sparql(), opts))
         }}
      end

    %{org: org, people: people}
  end

  @doc "Expected organization subject IRI for a seed `{tenant, code}`."
  def org_iri(tenant, code), do: org_subject_prefix() <> encode(tenant) <> "/" <> encode(code)

  @doc "Expected person subject IRI for an id."
  def person_iri(id), do: person_subject_prefix() <> id

  @doc "Percent-encoding identical to the subject-IRI law (`URI.char_unreserved?/1`)."
  def encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @doc "Appends `:postgres` to the ExUnit exclusions unless `ASH_R2RML_POSTGRES_URL` is set."
  def exclude_postgres_by_default! do
    if System.get_env("ASH_R2RML_POSTGRES_URL") in [nil, ""] do
      excluded = Keyword.get(ExUnit.configuration(), :exclude, [])
      ExUnit.configure(exclude: Enum.uniq(excluded ++ [:postgres]))
    end

    :ok
  end

  # -- resource generation ----------------------------------------------------

  @doc """
  Defines `<name>.Domain`, `<name>.Organization` and `<name>.Person` on data-layer `kind`
  (`:ets | :sqlite | :postgres`). `repo` is required for `:sqlite` and `:postgres`.
  """
  defmacro define(name, kind, repo \\ nil) do
    name = Macro.expand(name, __CALLER__)
    kind = Macro.expand(kind, __CALLER__)
    repo = if repo, do: Macro.expand(repo, __CALLER__)

    domain = Module.concat(name, Domain)
    org = Module.concat(name, Organization)
    person = Module.concat(name, Person)
    data_layer = data_layer(kind)

    quote do
      defmodule unquote(domain) do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          resource unquote(org)
          resource unquote(person)
        end
      end

      defmodule unquote(org) do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: unquote(data_layer),
          extensions: [AshR2RML]

        unquote(layer_dsl(kind, repo, "contract_organizations"))

        r2rml do
          class_iri(unquote(class_iri(:org)))
          subject_template(unquote(org_subject_prefix() <> "{tenant_id}/{code}"))
          table_name("contract_organizations")

          attribute_mappings([
            {:code, unquote(pred(:org_code))},
            {:name, unquote(pred(:org_name))}
          ])
        end

        multitenancy do
          strategy :attribute
          attribute :tenant_id
        end

        actions do
          defaults [:read, :destroy]

          create :create do
            primary? true
            accept [:code, :name, :internal_tax_id]
          end
        end

        attributes do
          attribute :tenant_id, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
          attribute :name, :string, allow_nil?: false, public?: true
          attribute :internal_tax_id, :string, public?: true, sensitive?: true
        end
      end

      defmodule unquote(person) do
        use Ash.Resource,
          domain: unquote(domain),
          data_layer: unquote(data_layer),
          authorizers: [Ash.Policy.Authorizer],
          extensions: [AshR2RML]

        unquote(layer_dsl(kind, repo, "contract_people"))

        r2rml do
          class_iri(unquote(class_iri(:person)))
          subject_template(unquote(person_subject_prefix() <> "{id}"))
          table_name("contract_people")

          attribute_mappings([
            {:name, unquote(pred(:name))},
            {:age, unquote(pred(:age))},
            {:active, unquote(pred(:active))},
            {:score, unquote(pred(:score))},
            {:born_on, unquote(pred(:born_on))},
            {:joined_at, unquote(pred(:joined_at))},
            {:secret_note, unquote(pred(:secret_note))}
          ])
        end

        multitenancy do
          strategy :attribute
          attribute :tenant_id
        end

        actions do
          defaults [:read, :destroy]

          create :create do
            primary? true
            accept [:id, :org_code, :name, :age, :active, :score, :born_on, :joined_at, :secret_note, :ssn_token]
          end
        end

        policies do
          policy action_type([:create, :update, :destroy]) do
            authorize_if always()
          end

          policy action_type(:read) do
            authorize_if actor_attribute_equals(:role, :admin)
            authorize_if actor_attribute_equals(:role, :member)
          end
        end

        field_policies do
          field_policy [:secret_note] do
            authorize_if actor_attribute_equals(:role, :admin)
          end

          field_policy :* do
            authorize_if always()
          end
        end

        attributes do
          uuid_primary_key :id, writable?: true
          attribute :tenant_id, :string, allow_nil?: false, public?: true
          attribute :org_code, :string, public?: true
          attribute :name, :string, allow_nil?: false, public?: true
          attribute :age, :integer, public?: true
          attribute :active, :boolean, public?: true
          attribute :score, :float, public?: true
          attribute :born_on, :date, public?: true
          attribute :joined_at, :utc_datetime, public?: true
          attribute :secret_note, :string, public?: true
          attribute :ssn_token, :string, public?: true, sensitive?: true
        end

        relationships do
          belongs_to :organization, unquote(org) do
            source_attribute :org_code
            destination_attribute :code
            define_attribute? false
            public? true
          end
        end
      end
    end
  end

  defp data_layer(:ets), do: Ash.DataLayer.Ets
  defp data_layer(:sqlite), do: AshSqlite.DataLayer
  defp data_layer(:postgres), do: AshPostgres.DataLayer

  defp layer_dsl(:ets, _repo, _table) do
    quote do
      ets do
        private? true
      end
    end
  end

  defp layer_dsl(:sqlite, repo, table) do
    quote do
      sqlite do
        table unquote(table)
        repo(unquote(repo))
      end
    end
  end

  defp layer_dsl(:postgres, repo, table) do
    quote do
      postgres do
        table unquote(table)
        repo(unquote(repo))
      end
    end
  end
end

defmodule AshR2RML.DataLayerContract.Cases do
  @moduledoc """
  The data-layer contract as injectable tests. `use AshR2RML.DataLayerContract.Cases, layer: Mod`
  inside an `ExUnit.Case` module (after any `setup_all` that boots the layer's storage) injects
  one test per contract clause against the layer generated by
  `AshR2RML.DataLayerContract.define/3`.
  """

  defmacro __using__(opts) do
    layer = Macro.expand(Keyword.fetch!(opts, :layer), __CALLER__)

    quote do
      alias AshR2RML.DataLayerContract, as: C
      alias AshR2RML.OBDA.InMemory
      alias AshR2RML.{Refusal, Subject}

      setup do
        C.clear!(unquote(layer))
        C.seed!(unquote(layer))
        :ok
      end

      test "R2RML is byte-identical across input order and domain expansion" do
        org = C.resource(unquote(layer), :org)
        person = C.resource(unquote(layer), :person)

        assert {:ok, forward} = AshR2RML.R2RML.render([org, person])
        assert {:ok, backward} = AshR2RML.R2RML.render([person, org])
        assert {:ok, via_domain} = AshR2RML.R2RML.render([C.domain(unquote(layer))])

        assert forward == backward
        assert forward == via_domain
        assert forward =~ "rr:predicate <#{C.pred(:org_name)}>"

        # Intentional, documented layer divergence: AshPostgres columns are reachable by external SQL
        # engines that would bypass Ash policies, so Security.sanitize_mapping/2 strips every
        # field-policy-gated attribute from the rendered R2RML. Non-SQL layers keep them.
        if unquote(layer) == AshR2RML.DataLayerContract.Postgres do
          refute forward =~ "rr:predicate <#{C.pred(:born_on)}>"
        else
          assert forward =~ "rr:predicate <#{C.pred(:born_on)}>"
        end

        # secret_note is field-policy gated at read time (see the security cases).
        if unquote(layer) != AshR2RML.DataLayerContract.Postgres do
          assert forward =~ C.pred(:secret_note)
        end

        refute forward =~ C.pred(:ssn_token)
        refute forward =~ C.pred(:internal_tax_id)
      end

      test "subject IRI round-trips composite keys including 'acme/west #1'" do
        mapping = C.mapping(unquote(layer), :org)
        iri = C.org_subject_prefix() <> "t1/acme%2Fwest%20%231"

        assert Subject.to_iri(mapping, %{tenant_id: "t1", code: "acme/west #1"}) == {:ok, iri}
        assert Subject.from_iri(mapping, iri) == {:ok, %{tenant_id: "t1", code: "acme/west #1"}}
        assert C.org_iri("t1", "acme/west #1") == iri

        for {tenant, code, _name, _tax} <- C.orgs() do
          assert {:ok, iri} = Subject.to_iri(mapping, %{tenant_id: tenant, code: code})
          assert Subject.from_iri(mapping, iri) == {:ok, %{tenant_id: tenant, code: code}}
        end
      end

      test "InMemory subjects equal Subject.to_iri of the stored records" do
        org = C.resource(unquote(layer), :org)
        mapping = C.mapping(unquote(layer), :org)

        expected =
          for tenant <- C.tenants(), record <- Ash.read!(org, tenant: tenant, domain: C.domain(unquote(layer))) do
            assert {:ok, iri} = Subject.to_iri(mapping, record)
            iri
          end

        emitted =
          for tenant <- C.tenants(),
              row <- C.visible(C.run(unquote(layer), :org, C.org_sparql(), tenant: tenant)),
              do: row["s"]

        assert Enum.sort(emitted) == Enum.sort(expected)
        assert C.org_iri("t1", "acme/west #1") in emitted
      end

      test "bindings are independent of insertion order" do
        first = C.snapshot(unquote(layer))
        C.clear!(unquote(layer))
        C.seed!(unquote(layer), :reverse)

        assert C.snapshot(unquote(layer)) == first
      end

      test "tenant isolation: each tenant sees only its own organizations" do
        t1 = C.visible(C.run(unquote(layer), :org, C.org_sparql(), tenant: "t1"))
        t2 = C.visible(C.run(unquote(layer), :org, C.org_sparql(), tenant: "t2"))

        assert Enum.map(t1, & &1["code"]) |> Enum.sort() == ["acme/west #1", "plain"]
        assert Enum.map(t2, & &1["code"]) == ["zeta"]
        assert Enum.all?(t1, &String.starts_with?(&1["s"], C.org_subject_prefix() <> "t1/"))
      end

      test "a multitenant read without a tenant is refused, never widened" do
        assert {:error, %Refusal{}} = C.run(unquote(layer), :org, C.org_sparql())
      end

      test "person tenant isolation holds for every admitted role" do
        for role <- [:admin, :member] do
          rows = C.visible(C.run(unquote(layer), :person, C.person_sparql(), tenant: "t2", actor: C.actor(role)))
          assert Enum.map(rows, & &1["s"]) == [C.person_iri("00000000-0000-4000-8000-000000000003")]
        end
      end

      test "role matrix: admin, member, outsider and nil actor" do
        t1_ids = ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"]
        t1_subjects = Enum.map(t1_ids, &C.person_iri/1)

        for role <- [:admin, :member] do
          rows = C.visible(C.run(unquote(layer), :person, C.person_sparql(), tenant: "t1", actor: C.actor(role)))
          assert Enum.map(rows, & &1["s"]) |> Enum.sort() == t1_subjects
          assert Enum.map(rows, & &1["name"]) |> Enum.sort() == ["Ada", "Bob"]
        end

        for role <- [:outsider, nil] do
          result = C.run(unquote(layer), :person, C.person_sparql(), tenant: "t1", actor: C.actor(role))
          assert C.visible(result) == []
          refute inspect(result) =~ "Ada"
        end

        admin = C.visible(C.run(unquote(layer), :person, C.secret_sparql(), tenant: "t1", actor: C.actor(:admin)))
        assert Enum.map(admin, & &1["note"]) |> Enum.sort() == ["NOTE-ADA-SECRET", "NOTE-BOB-SECRET"]

        for role <- [:member, :outsider, nil] do
          result = C.run(unquote(layer), :person, C.secret_sparql(), tenant: "t1", actor: C.actor(role))
          assert C.visible(result) == []
          refute inspect(result) =~ "SECRET"
        end
      end

      test "sensitive attributes never reach the default graph; mapping one refuses" do
        for role <- [:admin, :member] do
          {:ok, graph} =
            InMemory.materialize(C.resource(unquote(layer), :person), C.mapping(unquote(layer), :person),
              domain: C.domain(unquote(layer)),
              tenant: "t1",
              actor: C.actor(role)
            )

          refute inspect(graph) =~ "SSN-"
        end

        {:ok, org_graph} =
          InMemory.materialize(C.resource(unquote(layer), :org), C.mapping(unquote(layer), :org),
            domain: C.domain(unquote(layer)),
            tenant: "t1"
          )

        refute inspect(org_graph) =~ "TAX-"

        tax_mapping =
          C.with_attribute(C.mapping(unquote(layer), :org), :internal_tax_id, C.pred(:internal_tax_id))

        assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} =
                 InMemory.materialize(C.resource(unquote(layer), :org), tax_mapping,
                   domain: C.domain(unquote(layer)),
                   tenant: "t1"
                 )

        assert {:ok, opted_in} =
                 InMemory.materialize(C.resource(unquote(layer), :org), tax_mapping,
                   domain: C.domain(unquote(layer)),
                   tenant: "t1",
                   allow_sensitive: true
                 )

        assert inspect(opted_in) =~ "TAX-ACME-WEST-0001"
      end
    end
  end
end

if Code.ensure_loaded?(AshSqlite.DataLayer) do
  defmodule AshR2RML.DataLayerContract.SqliteRepo do
    @moduledoc "Real AshSqlite repo for the contract; started per test module by `Db.start_sqlite!/0`."
    use AshSqlite.Repo, otp_app: :ash_r2rml
  end
end

defmodule AshR2RML.DataLayerContract.PostgresRepo do
  @moduledoc """
  Real `AshPostgres.Repo` for the `:postgres` contract; started by `Db.start_postgres!/0` only when
  `ASH_R2RML_POSTGRES_URL` is set.
  """
  use AshPostgres.Repo, otp_app: :ash_r2rml, warn_on_missing_ash_functions?: false

  def installed_extensions, do: []
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
end

defmodule AshR2RML.DataLayerContract.Db do
  @moduledoc """
  Boots real SQL storage (file-backed SQLite, or Postgres from `ASH_R2RML_POSTGRES_URL`) and
  creates the contract tables. Fails loudly when the backing store is unavailable.
  """

  @sqlite_ddl [
    "CREATE TABLE IF NOT EXISTS contract_organizations (tenant_id TEXT NOT NULL, code TEXT NOT NULL, " <>
      "name TEXT NOT NULL, internal_tax_id TEXT, PRIMARY KEY (tenant_id, code))",
    "CREATE TABLE IF NOT EXISTS contract_people (id TEXT PRIMARY KEY NOT NULL, tenant_id TEXT NOT NULL, " <>
      "org_code TEXT, name TEXT NOT NULL, age INTEGER, active INTEGER, score REAL, born_on TEXT, " <>
      "joined_at TEXT, secret_note TEXT, ssn_token TEXT)"
  ]

  @postgres_ddl [
    "CREATE TABLE IF NOT EXISTS contract_organizations (tenant_id TEXT NOT NULL, code TEXT NOT NULL, " <>
      "name TEXT NOT NULL, internal_tax_id TEXT, PRIMARY KEY (tenant_id, code))",
    "CREATE TABLE IF NOT EXISTS contract_people (id UUID PRIMARY KEY NOT NULL, tenant_id TEXT NOT NULL, " <>
      "org_code TEXT, name TEXT NOT NULL, age BIGINT, active BOOLEAN, score DOUBLE PRECISION, " <>
      "born_on DATE, joined_at TIMESTAMP(0), secret_note TEXT, ssn_token TEXT)"
  ]

  @doc "Starts the SQLite repo on a unique temp file and creates the tables. Returns the repo."
  def start_sqlite! do
    repo = Module.concat(AshR2RML.DataLayerContract, SqliteRepo)
    path = Path.join(System.tmp_dir!(), "ash_r2rml_contract_#{System.unique_integer([:positive])}.db")

    {:ok, pid} = repo.start_link(database: path, pool_size: 1)
    create_tables!(repo, @sqlite_ddl)

    ExUnit.Callbacks.on_exit(fn ->
      ref = Process.monitor(pid)
      Process.exit(pid, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        5_000 -> :ok
      end

      File.rm(path)
      File.rm(path <> "-shm")
      File.rm(path <> "-wal")
    end)

    repo
  end

  @doc "Starts the Postgres repo from `ASH_R2RML_POSTGRES_URL` and creates the tables."
  def start_postgres! do
    url =
      case System.get_env("ASH_R2RML_POSTGRES_URL") do
        value when value in [nil, ""] -> raise "ASH_R2RML_POSTGRES_URL is required for :postgres contract tests"
        value -> value
      end

    repo = AshR2RML.DataLayerContract.PostgresRepo

    case repo.start_link(url: url, pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    create_tables!(repo, @postgres_ddl)
    repo
  end

  defp create_tables!(repo, ddl) do
    Enum.each(ddl, &Ecto.Adapters.SQL.query!(repo, &1, []))
  end
end
