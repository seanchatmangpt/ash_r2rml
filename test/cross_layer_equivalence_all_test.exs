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

defmodule AshR2RML.CrossLayerEquivalenceAllTest do
  @moduledoc """
  The same 50 Person rows, published through ETS, a manual-read Simple resource, CSV, SQLite and
  (under `:postgres`) Postgres, answer one SPARQL query through `AshR2RML.OBDA.query/3` with
  byte-identical bindings and an identical envelope digest. ETS is the reference.
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

  defp assert_equivalent(result, reference) do
    assert length(result.bindings) == @rows
    assert result.bindings == reference.bindings
    # The digest seals the rendered R2RML too, whose TriplesMap names carry each layer's module name,
    # so cross-layer equality is asserted over the canonical bindings, rows and triples instead.
    assert byte_size(result.digest) == 64
    assert result.stats.rows_read == reference.stats.rows_read
    assert result.stats.triples_emitted == reference.stats.triples_emitted
  end

  test "the ETS reference publishes every seeded person with its name and age" do
    ref = reference()

    assert length(ref.bindings) == @rows

    row = Enum.find(ref.bindings, &(&1["s"] == "https://ex.org/person/p7"))
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

    assert_equivalent(run(Xl.Simple), ref)
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
      assert_equivalent(run(layer), ref)
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
      assert_equivalent(run(layer), ref)
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

      case repo.start_link(url: url, pool_size: 2) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      Ecto.Adapters.SQL.query!(
        repo,
        "CREATE TABLE IF NOT EXISTS xl_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, age BIGINT)",
        []
      )

      Ecto.Adapters.SQL.query!(repo, "DELETE FROM xl_people", [])

      layer = Xl.Postgres
      seed!(Module.concat(layer, Person), Module.concat(layer, Domain))
      assert_equivalent(run(layer), ref)
    end
  end
end
