# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

AshR2RML.DataLayerContract.exclude_postgres_by_default!()

defmodule AshR2RML.CrossLayerEquivalenceAll.SimpleRead do
  @moduledoc false
  use Ash.Resource.ManualRead

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    rows = Application.get_env(:ash_r2rml, :xl_all_simple_rows, [])

    {:ok, for({pid, name, age} <- rows, do: struct(query.resource, pid: pid, name: name, age: age))}
  end
end

alias AshR2RML.CrossLayerEquivalenceAll.Fixture

require Fixture

Fixture.define AshR2RML.CrossLayerEquivalenceAll.Ets, Ash.DataLayer.Ets, [] do
  ets do
    private? false
  end
end

Fixture.define AshR2RML.CrossLayerEquivalenceAll.Simple,
               Ash.DataLayer.Simple,
               manual: AshR2RML.CrossLayerEquivalenceAll.SimpleRead do
end

if Code.ensure_loaded?(AshCsv.DataLayer) do
  Fixture.define AshR2RML.CrossLayerEquivalenceAll.Csv, AshCsv.DataLayer, [] do
    csv do
      file(Path.join(System.tmp_dir!(), "ash_r2rml_xl_all_#{System.unique_integer([:positive])}.csv"))
      create?(true)
      header?(true)
      columns([:pid, :name, :age])
    end
  end
end

if Code.ensure_loaded?(AshSqlite.DataLayer) do
  defmodule AshR2RML.CrossLayerEquivalenceAll.SqliteRepo do
    @moduledoc false
    use AshSqlite.Repo, otp_app: :ash_r2rml
  end

  Fixture.define AshR2RML.CrossLayerEquivalenceAll.Sqlite, AshSqlite.DataLayer, [] do
    sqlite do
      table "xl_people"
      repo(AshR2RML.CrossLayerEquivalenceAll.SqliteRepo)
    end
  end
end

if Code.ensure_loaded?(AshPostgres.DataLayer) do
  defmodule AshR2RML.CrossLayerEquivalenceAll.PostgresRepo do
    @moduledoc false
    use AshPostgres.Repo, otp_app: :ash_r2rml, warn_on_missing_ash_functions?: false

    def installed_extensions, do: []
    def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
  end

  Fixture.define AshR2RML.CrossLayerEquivalenceAll.Postgres, AshPostgres.DataLayer, [] do
    postgres do
      table "xl_people"
      repo(AshR2RML.CrossLayerEquivalenceAll.PostgresRepo)
    end
  end
end

require AshR2RML.CrossLayerEquivalenceAll.TypedFixture, as: TypedFixture

TypedFixture.define AshR2RML.CrossLayerEquivalenceAll.TypedEts, Ash.DataLayer.Ets do
  ets do
    private? false
  end
end

if Code.ensure_loaded?(AshSqlite.DataLayer) do
  TypedFixture.define AshR2RML.CrossLayerEquivalenceAll.TypedSqlite, AshSqlite.DataLayer do
    sqlite do
      table "xl_typed_people"
      repo(AshR2RML.CrossLayerEquivalenceAll.SqliteRepo)
    end
  end
end

if Code.ensure_loaded?(AshPostgres.DataLayer) do
  TypedFixture.define AshR2RML.CrossLayerEquivalenceAll.TypedPostgres, AshPostgres.DataLayer do
    postgres do
      table "xl_typed_people"
      repo(AshR2RML.CrossLayerEquivalenceAll.PostgresRepo)
    end
  end
end

require AshR2RML.DataLayerContract.Shapes, as: Shapes

Shapes.define(AshR2RML.CrossLayerEquivalenceAll.ShapeEts, :ets)

if Code.ensure_loaded?(AshSqlite.DataLayer) do
  Shapes.define(AshR2RML.CrossLayerEquivalenceAll.ShapeSqlite, :sqlite, AshR2RML.CrossLayerEquivalenceAll.SqliteRepo)
end

if Code.ensure_loaded?(AshPostgres.DataLayer) do
  Shapes.define(
    AshR2RML.CrossLayerEquivalenceAll.ShapePostgres,
    :postgres,
    AshR2RML.CrossLayerEquivalenceAll.PostgresRepo
  )
end

defmodule AshR2RML.CrossLayerEquivalenceAllTest do
  @moduledoc """
  The same 50 Person rows, published through ETS, a manual-read Simple resource, CSV, SQLite and
  (under `:postgres`) Postgres, answer one SPARQL query through `AshR2RML.OBDA.query/3` with
  byte-identical bindings. The envelope digest seals the rendered R2RML, whose TriplesMap name embeds
  the layer's module name, so raw digests differ per layer; the digest is asserted equal across layers
  after that one name is normalized, and equal to a digest recomputed from the sealed inputs. ETS is
  the reference.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.CrossLayerEquivalenceAll, as: Xl

  @rows 50
  @sparql "SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }"

  defp seed!(resource, domain) do
    for i <- 1..@rows do
      resource
      |> Ash.Changeset.for_create(:create, %{pid: "p#{i}", name: "Person #{i}", age: i}, domain: domain)
      |> Ash.create!(domain: domain, authorize?: false)
    end

    :ok
  end

  defp run(layer) do
    resource = Module.concat(layer, Person)
    domain = Module.concat(layer, Domain)
    mapping = AshR2RML.Resource.Info.mapping!(resource)

    assert {:ok, result} =
             AshR2RML.OBDA.query([{resource, mapping}], @sparql,
               domain: domain,
               authorize?: false,
               allow_unauthorized: true
             )

    result
  end

  defp reference do
    layer = Xl.Ets
    resource = Module.concat(layer, Person)
    domain = Module.concat(layer, Domain)

    # ETS here is non-private (shared across tests): clear before seeding so seeding is idempotent.
    resource
    |> Ash.read!(domain: domain, authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, domain: domain, authorize?: false))

    seed!(resource, domain)
    run(layer)
  end

  # The rendered R2RML of a layer, plus its TriplesMap name (Module.split joined with "_", renderers.ex).
  defp rendered(layer) do
    resource = Module.concat(layer, Person)
    mapping = AshR2RML.Resource.Info.mapping!(resource)
    {:ok, ttl} = AshR2RML.R2RML.render(%AshR2RML.Mapping.Bundle{resources: [mapping]})
    {ttl, "#" <> (resource |> Module.split() |> Enum.join("_"))}
  end

  # The digest seals frame(ttl) <> frame(sparql) <> frame(bindings). The only layer-dependent byte of
  # the ttl is the TriplesMap name, so replacing it with a fixed token must make digests equal.
  defp normalized_digest(layer, result) do
    {ttl, name} = rendered(layer)
    assert ttl =~ name
    AshR2RML.OBDA.Result.digest(String.replace(ttl, name, "#NormalizedPerson"), @sparql, result.bindings)
  end

  defp assert_digest_equivalent(layer, result, reference) do
    {ttl, _name} = rendered(layer)
    assert result.digest == AshR2RML.OBDA.Result.digest(ttl, @sparql, result.bindings)
    assert normalized_digest(layer, result) == normalized_digest(Xl.Ets, reference)

    if layer != Xl.Ets do
      # The digest differs across layers only through the TriplesMap name.
      refute result.digest == reference.digest
    end
  end

  defp assert_equivalent(layer, result, reference) do
    assert length(result.bindings) == @rows
    assert result.bindings == reference.bindings
    assert byte_size(result.digest) == 64
    assert_digest_equivalent(layer, result, reference)
    assert result.stats.rows_read == reference.stats.rows_read
    assert result.stats.triples_emitted == reference.stats.triples_emitted
  end

  # -- typed court: terms compared with datatype IRI + lexical form + language intact ----------------

  alias AshR2RML.DataLayerContract, as: C

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @xsd_integer "http://www.w3.org/2001/XMLSchema#integer"
  @xsd_boolean "http://www.w3.org/2001/XMLSchema#boolean"
  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"
  @xsd_date "http://www.w3.org/2001/XMLSchema#date"
  @xsd_datetime "http://www.w3.org/2001/XMLSchema#dateTime"

  @typed_base ~U[2026-01-01 00:00:00.000000Z]

  defp typed_attrs(i) do
    %{
      pid: "p#{i}",
      name: "Person #{i}",
      age: i,
      active: rem(i, 2) == 0,
      price: Decimal.new("#{i}.25"),
      born_on: Date.add(~D[1990-01-01], i),
      seen_at: DateTime.add(@typed_base, i * 1_000_123, :microsecond),
      ref: "00000000-0000-4000-8000-" <> String.pad_leading("#{i}", 12, "0")
    }
  end

  defp typed_seed!(layer) do
    resource = Module.concat(layer, Person)
    domain = Module.concat(layer, Domain)

    for i <- 1..@rows do
      resource
      |> Ash.Changeset.for_create(:create, typed_attrs(i), domain: domain)
      |> Ash.create!(domain: domain, authorize?: false)
    end

    :ok
  end

  defp typed_reference do
    layer = Xl.TypedEts
    resource = Module.concat(layer, Person)
    domain = Module.concat(layer, Domain)

    resource
    |> Ash.read!(domain: domain, authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, domain: domain, authorize?: false))

    typed_seed!(layer)
    C.typed_triples(layer, :person)
  end

  defp object_of(triples, subject_iri, predicate_iri) do
    for {{:iri, ^subject_iri}, {:iri, ^predicate_iri}, object} <- triples, do: object
  end

  # No layer is declared to differ: any divergence in datatype IRI, lexical form or language between
  # a layer and the ETS reference is a real finding and fails here, never flattened away.
  defp assert_typed_equivalent(layer) do
    reference = typed_reference()
    typed_seed!(layer)
    actual = C.typed_triples(layer, :person)

    assert length(actual) == length(reference)
    assert actual == reference
  end

  test "typed terms keep datatype and lexical form where string flattening cannot" do
    integer = RDF.XSD.Integer.new(7)
    string = RDF.XSD.String.new("7")
    lang = RDF.LangString.new("7", language: "en")

    assert to_string(RDF.Literal.lexical(integer)) == to_string(RDF.Literal.lexical(string))
    refute C.typed_term(integer) == C.typed_term(string)
    refute C.typed_term(string) == C.typed_term(lang)
    assert C.typed_term(integer) == {:literal, @xsd_integer, "7", nil}
    assert C.typed_term(lang) == {:literal, "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString", "7", "en"}
  end

  test "the ETS reference publishes every attribute as its own typed literal" do
    reference = typed_reference()
    subject = "urn:uuid:p7"

    assert [{:literal, @xsd_string, "Person 7", nil}] = object_of(reference, subject, "http://schema.org/name")
    assert [{:literal, @xsd_integer, "7", nil}] = object_of(reference, subject, "http://schema.org/age")
    assert [{:literal, @xsd_boolean, "false", nil}] = object_of(reference, subject, "http://schema.org/active")
    assert [{:literal, @xsd_decimal, price, nil}] = object_of(reference, subject, "http://schema.org/price")
    assert [{:literal, @xsd_date, "1990-01-08", nil}] = object_of(reference, subject, "http://schema.org/birthDate")

    assert [{:literal, @xsd_datetime, seen_at, nil}] =
             object_of(reference, subject, "http://schema.org/dateModified")

    assert [{:literal, @xsd_string, "00000000-0000-4000-8000-000000000007", nil}] =
             object_of(reference, subject, "http://schema.org/identifier")

    assert price == "7.25"
    # microsecond precision survives into the lexical form (7 * 1_000_123 us = 7.000861 s)
    assert String.starts_with?(seen_at, "2026-01-01T00:00:07.000861")

    subjects =
      for {{:iri, s}, {:iri, "http://schema.org/age"}, _} <- reference, do: s

    assert length(subjects) == @rows
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    @tag :sqlite
    test "SQLite typed literals (datatype + lexical) equal ETS" do
      repo = Xl.SqliteRepo
      path = Path.join(System.tmp_dir!(), "ash_r2rml_xl_typed_#{System.unique_integer([:positive])}.db")

      {:ok, pid} = repo.start_link(database: path, pool_size: 1)

      Ecto.Adapters.SQL.query!(
        repo,
        "CREATE TABLE IF NOT EXISTS xl_typed_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, age INTEGER, " <>
          "active INTEGER, price TEXT, born_on TEXT, seen_at TEXT, ref TEXT)",
        []
      )

      on_exit(fn ->
        ref = Process.monitor(pid)
        Process.exit(pid, :shutdown)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          5_000 -> :ok
        end

        for suffix <- ["", "-shm", "-wal"], do: File.rm(path <> suffix)
      end)

      # price is a TEXT column on purpose: SQLite has no decimal type, and a NUMERIC column would
      # round-trip "7.25" through a binary float. The fixture asserts the lexical form survives.
      assert_typed_equivalent(Xl.TypedSqlite)
    end
  end

  if Code.ensure_loaded?(AshPostgres.DataLayer) do
    @tag :postgres
    test "Postgres typed literals (datatype + lexical) equal ETS" do
      repo = Xl.PostgresRepo

      url =
        case System.get_env("ASH_R2RML_POSTGRES_URL") do
          value when value in [nil, ""] -> flunk("ASH_R2RML_POSTGRES_URL is required for :postgres tests")
          value -> value
        end

      start_supervised!(%{id: repo, start: {repo, :start_link, [[url: url, pool_size: 2]]}})

      Ecto.Adapters.SQL.query!(
        repo,
        "CREATE TABLE IF NOT EXISTS xl_typed_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, age BIGINT, " <>
          "active BOOLEAN, price NUMERIC, born_on DATE, seen_at TIMESTAMP(6), ref UUID)",
        []
      )

      Ecto.Adapters.SQL.query!(repo, "DELETE FROM xl_typed_people", [])

      assert_typed_equivalent(Xl.TypedPostgres)
    end
  end

  # -- shape court: NULLs, float/time/naive/utc, reference join, ORDER BY / LIMIT / FILTER ------------

  @xsd_double "http://www.w3.org/2001/XMLSchema#double"
  @xsd_time "http://www.w3.org/2001/XMLSchema#time"

  defp shape_reference do
    Shapes.reseed!(Xl.ShapeEts)
    Shapes.observe(Xl.ShapeEts)
  end

  # Any divergence in datatype IRI, lexical form, row order or refusal between a layer and the ETS
  # reference is a real finding. No layer is declared to differ.
  defp assert_shape_equivalent(layer) do
    reference = shape_reference()
    Shapes.reseed!(layer)
    actual = Shapes.observe(layer)

    assert Map.keys(actual) == Map.keys(reference)

    for key <- Map.keys(reference) do
      assert {key, actual[key]} == {key, reference[key]}
    end

    # OBDA.query/3 envelope shapes: ORDER BY + LIMIT/OFFSET, DISTINCT, OPTIONAL, UNION, COUNT and the
    # unsupported-tail refusal, compared with typed terms and identical refusal codes.
    obda_reference = Shapes.obda_observe(Xl.ShapeEts)
    obda_actual = Shapes.obda_observe(layer)

    for {name, _} <- Shapes.obda_shapes() do
      assert {name, obda_actual[name]} == {name, obda_reference[name]}
    end
  end

  defp objects(triples, subject_iri, predicate_iri), do: object_of(triples, subject_iri, predicate_iri)

  test "shape reference: NULLs publish no triple, temporal and float types keep their datatype" do
    reference = shape_reference()
    triples = reference.triples

    assert [{:literal, @xsd_double, _, nil}] = objects(triples, "urn:uuid:p1", "http://schema.org/ratingValue")
    assert [{:literal, @xsd_time, "03:04:05", nil}] = objects(triples, "urn:uuid:p1", "http://schema.org/startTime")
    assert [{:literal, @xsd_datetime, naive, nil}] = objects(triples, "urn:uuid:p1", "http://schema.org/startDate")
    assert [{:literal, @xsd_datetime, utc, nil}] = objects(triples, "urn:uuid:p1", "http://schema.org/dateModified")
    assert String.starts_with?(naive, "2026-01-02T03:04:05")
    assert String.starts_with?(utc, "2026-01-02T03:04:05")

    # p3 has NULL score and NULL seen_at; p2 has NULL age; p5 is NULL everywhere but its name.
    assert objects(triples, "urn:uuid:p3", "http://schema.org/ratingValue") == []
    assert objects(triples, "urn:uuid:p3", "http://schema.org/dateModified") == []
    assert objects(triples, "urn:uuid:p2", "http://schema.org/age") == []

    assert [{:literal, @xsd_string, "Ed", nil}] = objects(triples, "urn:uuid:p5", "http://schema.org/name")

    p5_predicates = for {{:iri, "urn:uuid:p5"}, {:iri, p}, _} <- triples, do: p
    assert Enum.sort(p5_predicates) == ["http://schema.org/name", "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"]

    # reference object map: org_code is published as the parent's subject IRI, NULL org_code as nothing
    assert [{:iri, "urn:uuid:org/acme"}] = objects(triples, "urn:uuid:p1", "http://schema.org/memberOf")
    assert objects(triples, "urn:uuid:p3", "http://schema.org/memberOf") == []
  end

  test "shape reference: ORDER BY, LIMIT, FILTER and join return the expected rows" do
    shape_reference()
    plain = &Shapes.plain_rows(Xl.ShapeEts, Keyword.fetch!(Shapes.shapes(), &1))

    # LIMIT/OFFSET are applied by the OBDA envelope (obda.ex Modifiers.run), not by raw InMemory.query.
    assert plain.(:order_limit) |> Enum.map(& &1["name"]) |> Enum.sort() == ["Ada", "Bob", "Di"]

    # NULL age rows (p2, p5) never match; 29 is filtered out. Row order is the OBDA envelope's job.
    assert plain.(:filter) |> Enum.map(&String.to_integer(&1["age"])) |> Enum.sort() == [36, 41]

    assert plain.(:null_dropped) |> Enum.map(& &1["s"]) |> Enum.sort() == ["urn:uuid:p1", "urn:uuid:p3", "urn:uuid:p4"]

    assert plain.(:join) |> Enum.map(&{&1["p"], &1["o"], &1["oname"]}) |> Enum.sort() == [
             {"urn:uuid:p1", "urn:uuid:org/acme", "Acme"},
             {"urn:uuid:p2", "urn:uuid:org/plain", "Plain Org"},
             {"urn:uuid:p4", "urn:uuid:org/acme", "Acme"}
           ]

    observation = shape_reference()

    for name <- Keyword.keys(Shapes.shapes()) do
      assert {:ok, [_ | _]} = observation[name]
    end
  end

  test "OBDA shape reference: LIMIT/OFFSET slice the ordered rows; unsupported tail is a typed refusal" do
    Shapes.reseed!(Xl.ShapeEts)
    observed = Shapes.obda_observe(Xl.ShapeEts)
    name_of = fn {:ok, rows} -> Enum.map(rows, & &1["name"]) end
    native = fn names -> Enum.map(names, &{:native, inspect(&1)}) end

    assert name_of.(observed.order_limit_offset) == native.(["Ada", "Bob"])
    assert name_of.(observed.order_desc_limit) == native.(["Plain Org", "Ed", "Di"])
    assert observed.unsupported_order_expr == {:error, :REFUSED_UNSUPPORTED_SPARQL_FEATURE}
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    @tag :sqlite
    test "SQLite shape court (NULLs, float, time, naive, utc, join, ORDER BY/LIMIT/FILTER) equals ETS" do
      repo = Xl.SqliteRepo
      path = Path.join(System.tmp_dir!(), "ash_r2rml_xl_shape_#{System.unique_integer([:positive])}.db")

      {:ok, pid} = repo.start_link(database: path, pool_size: 1)

      on_exit(fn ->
        ref = Process.monitor(pid)
        Process.exit(pid, :shutdown)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          5_000 -> :ok
        end

        for suffix <- ["", "-shm", "-wal"], do: File.rm(path <> suffix)
      end)

      Shapes.reset_tables!(repo, Shapes.sqlite_ddl())
      assert_shape_equivalent(Xl.ShapeSqlite)
    end
  end

  if Code.ensure_loaded?(AshPostgres.DataLayer) do
    @tag :postgres
    test "Postgres shape court (NULLs, float, time, naive, utc, join, ORDER BY/LIMIT/FILTER) equals ETS" do
      repo = Xl.PostgresRepo

      url =
        case System.get_env("ASH_R2RML_POSTGRES_URL") do
          value when value in [nil, ""] -> flunk("ASH_R2RML_POSTGRES_URL is required for :postgres tests")
          value -> value
        end

      start_supervised!(%{id: repo, start: {repo, :start_link, [[url: url, pool_size: 2]]}})

      Shapes.reset_tables!(repo, Shapes.postgres_ddl())
      assert_shape_equivalent(Xl.ShapePostgres)
    end
  end

  test "the ETS reference publishes every seeded person with its name and age" do
    ref = reference()

    assert length(ref.bindings) == @rows

    row = Enum.find(ref.bindings, &(&1["s"] == "urn:uuid:p7"))
    assert row["n"] == "Person 7"
    assert to_string(row["a"]) == "7"
    assert is_binary(ref.digest)
  end

  test "Simple (manual read over an in-test list) equals ETS" do
    ref = reference()

    Application.put_env(
      :ash_r2rml,
      :xl_all_simple_rows,
      for(i <- 1..@rows, do: {"p#{i}", "Person #{i}", i})
    )

    on_exit(fn -> Application.delete_env(:ash_r2rml, :xl_all_simple_rows) end)

    assert_equivalent(Xl.Simple, run(Xl.Simple), ref)
  end

  if Code.ensure_loaded?(AshCsv.DataLayer) do
    @tag :csv
    test "CSV (real temp file) equals ETS" do
      ref = reference()
      layer = Xl.Csv
      resource = Module.concat(layer, Person)
      path = AshCsv.DataLayer.Info.file(resource)

      File.rm(path)
      on_exit(fn -> File.rm(path) end)

      seed!(resource, Module.concat(layer, Domain))
      assert_equivalent(layer, run(layer), ref)
    end
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    @tag :sqlite
    test "SQLite (real temp file) equals ETS" do
      ref = reference()
      repo = Xl.SqliteRepo
      path = Path.join(System.tmp_dir!(), "ash_r2rml_xl_all_#{System.unique_integer([:positive])}.db")

      {:ok, pid} = repo.start_link(database: path, pool_size: 1)

      Ecto.Adapters.SQL.query!(
        repo,
        "CREATE TABLE IF NOT EXISTS xl_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, age INTEGER)",
        []
      )

      on_exit(fn ->
        ref = Process.monitor(pid)
        Process.exit(pid, :shutdown)

        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          5_000 -> :ok
        end

        for suffix <- ["", "-shm", "-wal"], do: File.rm(path <> suffix)
      end)

      layer = Xl.Sqlite
      seed!(Module.concat(layer, Person), Module.concat(layer, Domain))
      assert_equivalent(layer, run(layer), ref)
    end
  end

  if Code.ensure_loaded?(AshPostgres.DataLayer) do
    @tag :postgres
    test "Postgres (ASH_R2RML_POSTGRES_URL) equals ETS" do
      ref = reference()
      repo = Xl.PostgresRepo

      url =
        case System.get_env("ASH_R2RML_POSTGRES_URL") do
          value when value in [nil, ""] -> flunk("ASH_R2RML_POSTGRES_URL is required for :postgres tests")
          value -> value
        end

      start_supervised!(%{id: repo, start: {repo, :start_link, [[url: url, pool_size: 2]]}})

      Ecto.Adapters.SQL.query!(
        repo,
        "CREATE TABLE IF NOT EXISTS xl_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, age BIGINT)",
        []
      )

      Ecto.Adapters.SQL.query!(repo, "DELETE FROM xl_people", [])

      layer = Xl.Postgres
      seed!(Module.concat(layer, Person), Module.concat(layer, Domain))
      assert_equivalent(layer, run(layer), ref)
    end
  end
end
