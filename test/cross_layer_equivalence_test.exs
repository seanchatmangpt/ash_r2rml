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

    assert {:ok, [_, _]} = snapshot.org["t1"]
    assert {:ok, [_]} = snapshot.org["t2"]
    assert {:ok, [_, _]} = snapshot.people[{"t1", :admin}].people
    assert {:ok, [_, _]} = snapshot.people[{"t1", :admin}].secrets
    assert {:ok, [_, _]} = snapshot.people[{"t1", :member}].people
    assert {:ok, [_]} = snapshot.people[{"t2", :admin}].people

    # Positive controls above (admin/member see rows) make these denials meaningful. A denial is a
    # typed refusal or an explicit empty-ok, never rows.
    denied = fn
      {:ok, []} -> true
      {:error, code} when is_atom(code) -> true
      _ -> false
    end

    assert denied.(snapshot.people[{"t1", :member}].secrets)

    for role <- [:outsider, nil] do
      assert denied.(snapshot.people[{"t1", role}].people)
      assert denied.(snapshot.people[{"t1", role}].secrets)
    end
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
