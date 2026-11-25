# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Real file-backed AshSqlite fixture for bench/b3_b4_query.exs. Mirrors the SQLite provisioning
# of test/support/data_layer_contract.ex (repo module, unique temp file, DDL, start_link).
# Require only when Code.ensure_loaded?(AshSqlite.DataLayer) holds.

defmodule Bench.SqliteFixture.Repo do
  use AshSqlite.Repo, otp_app: :ash_r2rml
end

defmodule Bench.SqliteFixture.Dom do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource Bench.SqliteFixture.Org
    resource Bench.SqliteFixture.Person
  end
end

defmodule Bench.SqliteFixture.Org do
  use Ash.Resource, domain: Bench.SqliteFixture.Dom, data_layer: AshSqlite.DataLayer

  sqlite do
    table "bench_orgs"
    repo Bench.SqliteFixture.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:oid, :title]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :oid, :string, public?: true
    attribute :title, :string, public?: true
  end
end

defmodule Bench.SqliteFixture.Person do
  use Ash.Resource, domain: Bench.SqliteFixture.Dom, data_layer: AshSqlite.DataLayer

  sqlite do
    table "bench_people"
    repo Bench.SqliteFixture.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:pid, :name, :age, :oid]
    end
  end

  attributes do
    attribute :pid, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    attribute :age, :integer, public?: true
    attribute :oid, :string, public?: true
  end
end

defmodule Bench.SqliteFixture do
  @moduledoc false

  alias Bench.SqliteFixture.{Dom, Org, Person, Repo}

  @ddl [
    "CREATE TABLE IF NOT EXISTS bench_orgs (id TEXT PRIMARY KEY NOT NULL, oid TEXT, title TEXT)",
    "CREATE TABLE IF NOT EXISTS bench_people (pid TEXT PRIMARY KEY NOT NULL, name TEXT, " <>
      "age INTEGER, oid TEXT)",
    "CREATE INDEX IF NOT EXISTS bench_orgs_oid ON bench_orgs (oid)"
  ]

  @doc "Starts the repo on a unique temp file and creates the tables. Returns a handle."
  def start! do
    {:ok, _} = Application.ensure_all_started(:ash_sqlite)

    path =
      Path.join(System.tmp_dir!(), "ash_r2rml_bench_#{System.unique_integer([:positive])}.db")

    {:ok, pid} = Repo.start_link(database: path, pool_size: 1)
    Enum.each(@ddl, &Ecto.Adapters.SQL.query!(Repo, &1, []))
    %{repo: Repo, pid: pid, path: path, dom: Dom, org: Org, person: Person}
  end

  @doc "Seeds `orgs` Org rows and `people` Person rows through Ash bulk create."
  def seed!(orgs, people) do
    org_inputs = for i <- 1..orgs, do: %{oid: "o#{i}", title: "Org #{i}"}

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(org_inputs, Org, :create,
        domain: Dom,
        batch_size: 500,
        return_errors?: true
      )

    person_inputs =
      for i <- 1..people do
        %{pid: "p#{i}", name: "Person #{i}", age: 18 + rem(i, 60), oid: "o#{rem(i, orgs) + 1}"}
      end

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(person_inputs, Person, :create,
        domain: Dom,
        batch_size: 500,
        return_errors?: true
      )

    :ok
  end

  @doc "Stops the repo and removes the database files."
  def stop!(%{pid: pid, path: path}) do
    ref = Process.monitor(pid)
    Process.unlink(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      5_000 -> :ok
    end

    for suffix <- ["", "-shm", "-wal"], do: File.rm(path <> suffix)
    :ok
  end
end
