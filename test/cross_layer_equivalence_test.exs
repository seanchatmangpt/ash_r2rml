# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

AshR2RML.DataLayerContract.exclude_postgres_by_default!()

defmodule AshR2RML.CrossLayerEquivalenceTest do
  @moduledoc """
  Canonical bindings published through `AshR2RML.OBDA.InMemory` are equal across data layers:
  the same seed rows, the same SPARQL, every tenant and every actor role yield identical
  results. ETS is the reference; SQLite and Postgres are compared against it when available.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.DataLayerContract, as: C

  @ets AshR2RML.DataLayerContract.Ets

  defp reference_snapshot do
    C.clear!(@ets)
    C.seed!(@ets)
    C.snapshot(@ets)
  end

  test "the reference snapshot publishes organizations, people and gated secrets per tenant and role" do
    snapshot = reference_snapshot()

    assert length(snapshot.org["t1"]) == 2
    assert length(snapshot.org["t2"]) == 1
    assert length(snapshot.people[{"t1", :admin}].people) == 2
    assert length(snapshot.people[{"t1", :admin}].secrets) == 2
    assert length(snapshot.people[{"t1", :member}].people) == 2
    assert snapshot.people[{"t1", :member}].secrets == []
    assert snapshot.people[{"t1", :outsider}] == %{people: [], secrets: []}
    assert snapshot.people[{"t1", nil}] == %{people: [], secrets: []}
    assert length(snapshot.people[{"t2", :admin}].people) == 1
  end

  test "ETS snapshot is stable across insertion order" do
    first = reference_snapshot()
    C.clear!(@ets)
    C.seed!(@ets, :reverse)
    assert C.snapshot(@ets) == first
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    @tag :sqlite
    test "SQLite bindings equal ETS bindings" do
      reference = reference_snapshot()
      AshR2RML.DataLayerContract.Db.start_sqlite!()

      sqlite = AshR2RML.DataLayerContract.Sqlite
      C.clear!(sqlite)
      C.seed!(sqlite)

      assert C.snapshot(sqlite) == reference
    end
  end

  if Code.ensure_loaded?(AshPostgres.DataLayer) do
    @tag :postgres
    test "Postgres bindings equal ETS bindings" do
      reference = reference_snapshot()
      AshR2RML.DataLayerContract.Db.start_postgres!()

      postgres = AshR2RML.DataLayerContract.Postgres
      C.clear!(postgres)
      C.seed!(postgres)

      assert C.snapshot(postgres) == reference
    end
  end
end
