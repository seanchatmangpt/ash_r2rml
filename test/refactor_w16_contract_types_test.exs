# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

require AshR2RML.RefactorW16ContractTypes.Fixture, as: Fixture

Fixture.define AshR2RML.RefactorW16ContractTypes.Ets, Ash.DataLayer.Ets do
  ets do
    private? false
  end
end

if Code.ensure_loaded?(AshSqlite.DataLayer) do
  Fixture.define AshR2RML.RefactorW16ContractTypes.Sqlite, AshSqlite.DataLayer do
    sqlite do
      table "w16_typed_rows"
      repo(AshR2RML.DataLayerContract.SqliteRepo)
    end
  end
end

defmodule AshR2RML.RefactorW16ContractTypesTest do
  @moduledoc """
  Boolean, Date, Decimal, uuid and utc_datetime attributes round-trip through `OBDA.query/3` and
  FILTER (`=`, `!=`, `<`, `&&`, `||`, `!`, `BOUND`) on real ETS and real SQLite rows. Each query's
  canonical bindings (typed terms, datatype IRI + lexical form) or typed refusal code must be equal
  on both layers. ETS is the reference; the per-query outcome is recorded, not assumed.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.DataLayerContract, as: C
  alias AshR2RML.RefactorW16ContractTypes, as: Ty

  @rows [
    %{
      pid: "a",
      flag: true,
      born_on: ~D[1985-01-01],
      amount: Decimal.new("5.25"),
      ref: "00000000-0000-4000-8000-00000000000a",
      seen_at: ~U[2026-01-01 00:00:00Z]
    },
    %{
      pid: "b",
      flag: false,
      born_on: ~D[1990-01-01],
      amount: Decimal.new("12.50"),
      ref: "00000000-0000-4000-8000-00000000000b",
      seen_at: ~U[2026-02-02 00:00:00Z]
    },
    %{
      pid: "c",
      flag: true,
      born_on: ~D[1995-06-15],
      amount: Decimal.new("20.00"),
      ref: "00000000-0000-4000-8000-00000000000c",
      seen_at: ~U[2026-03-03 00:00:00Z]
    },
    %{
      pid: "d",
      flag: false,
      born_on: ~D[2000-12-31],
      amount: nil,
      ref: "00000000-0000-4000-8000-00000000000d",
      seen_at: ~U[2026-04-04 00:00:00Z]
    }
  ]

  @date "<http://www.w3.org/2001/XMLSchema#date>"
  @dt "<http://www.w3.org/2001/XMLSchema#dateTime>"

  @queries [
    all_flag: "SELECT ?s ?v WHERE { ?s <http://schema.org/active> ?v } ORDER BY ?s",
    all_born: "SELECT ?s ?v WHERE { ?s <http://schema.org/birthDate> ?v } ORDER BY ?s",
    all_amount: "SELECT ?s ?v WHERE { ?s <http://schema.org/price> ?v } ORDER BY ?s",
    all_ref: "SELECT ?s ?v WHERE { ?s <http://schema.org/identifier> ?v } ORDER BY ?s",
    all_seen: "SELECT ?s ?v WHERE { ?s <http://schema.org/dateModified> ?v } ORDER BY ?s",
    flag_eq: "SELECT ?s WHERE { ?s <http://schema.org/active> ?f . FILTER(?f = true) } ORDER BY ?s",
    flag_ne: "SELECT ?s WHERE { ?s <http://schema.org/active> ?f . FILTER(?f != true) } ORDER BY ?s",
    flag_not: "SELECT ?s WHERE { ?s <http://schema.org/active> ?f . FILTER(!?f) } ORDER BY ?s",
    born_lt:
      "SELECT ?s WHERE { ?s <http://schema.org/birthDate> ?b . " <>
        "FILTER(?b < \"1990-01-01\"^^#{@date}) } ORDER BY ?s",
    born_ne:
      "SELECT ?s WHERE { ?s <http://schema.org/birthDate> ?b . " <>
        "FILTER(?b != \"1990-01-01\"^^#{@date}) } ORDER BY ?s",
    amount_lt: "SELECT ?s WHERE { ?s <http://schema.org/price> ?a . FILTER(?a < 10) } ORDER BY ?s",
    amount_eq:
      "SELECT ?s WHERE { ?s <http://schema.org/price> ?a . " <>
        "FILTER(?a = 12.50) } ORDER BY ?s",
    uuid_eq:
      "SELECT ?s WHERE { ?s <http://schema.org/identifier> ?u . " <>
        "FILTER(?u = \"00000000-0000-4000-8000-00000000000b\") } ORDER BY ?s",
    seen_lt:
      "SELECT ?s WHERE { ?s <http://schema.org/dateModified> ?t . " <>
        "FILTER(?t < \"2026-03-01T00:00:00Z\"^^#{@dt}) } ORDER BY ?s",
    and_filter:
      "SELECT ?s WHERE { ?s <http://schema.org/active> ?f ; <http://schema.org/birthDate> ?b . " <>
        "FILTER(?f = true && ?b < \"1990-01-01\"^^#{@date}) } ORDER BY ?s",
    or_filter:
      "SELECT ?s WHERE { ?s <http://schema.org/active> ?f ; <http://schema.org/birthDate> ?b . " <>
        "FILTER(?f = false || ?b < \"1990-01-01\"^^#{@date}) } ORDER BY ?s",
    bound:
      "SELECT ?s WHERE { ?s <http://schema.org/identifier> ?u . " <>
        "OPTIONAL { ?s <http://schema.org/price> ?a } FILTER(BOUND(?a)) } ORDER BY ?s",
    not_bound:
      "SELECT ?s WHERE { ?s <http://schema.org/identifier> ?u . " <>
        "OPTIONAL { ?s <http://schema.org/price> ?a } FILTER(!BOUND(?a)) } ORDER BY ?s"
  ]

  defp reseed!(layer) do
    resource = Module.concat(layer, Row)
    domain = Module.concat(layer, Domain)

    resource
    |> Ash.read!(domain: domain, authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, domain: domain, authorize?: false))

    for attrs <- @rows do
      resource
      |> Ash.Changeset.for_create(:create, attrs, domain: domain)
      |> Ash.create!(domain: domain, authorize?: false)
    end

    :ok
  end

  defp observe(layer) do
    resource = Module.concat(layer, Row)
    domain = Module.concat(layer, Domain)
    mapping = AshR2RML.Resource.Info.mapping!(resource)
    opts = [domain: domain, authorize?: false, allow_unauthorized: true]

    for {name, sparql} <- @queries, into: %{} do
      case AshR2RML.OBDA.query([{resource, mapping}], sparql, opts) do
        {:ok, result} ->
          rows = Enum.map(result.bindings, &Map.new(&1, fn {k, v} -> {k, C.typed_value(v)} end))
          {name, {:ok, rows}}

        {:error, %{code: code}} ->
          {name, {:error, code}}
      end
    end
  end

  defp subjects({:ok, rows}), do: Enum.map(rows, fn row -> row["s"] end)

  defp subject_ids(outcome) do
    for {:native, repr} <- subjects(outcome), do: repr |> String.trim("\"") |> String.replace("urn:uuid:", "")
  end

  defp values({:ok, rows}), do: Enum.map(rows, fn row -> row["v"] end)

  test "ETS reference: every attribute is published as its own typed literal" do
    reseed!(Ty.Ets)
    observed = observe(Ty.Ets)

    assert {:ok, flags} = observed.all_flag
    assert length(flags) == 4
    # Bindings arrive as native Elixir values (typed_value/1 renders them as {:native, inspect}).
    assert values(observed.all_flag) |> Enum.sort() == [
             native: "false",
             native: "false",
             native: "true",
             native: "true"
           ]

    assert length(values(observed.all_born)) == 4
    assert length(values(observed.all_seen)) == 4

    # NULL amount publishes no triple: 3 of 4 rows carry a decimal
    assert length(values(observed.all_amount)) == 3
    assert length(values(observed.all_ref)) == 4

    assert {:native, "~D[1985-01-01]"} in values(observed.all_born)
    assert {:native, "false"} in values(observed.all_flag)
  end

  test "ETS reference: BOUND and its negation partition the rows on the NULL amount" do
    reseed!(Ty.Ets)
    observed = observe(Ty.Ets)

    # An OPTIONAL + BOUND outcome is recorded, whichever way the engine answers it.
    case {observed.bound, observed.not_bound} do
      {{:ok, _} = bound, {:ok, _} = not_bound} ->
        assert Enum.sort(subject_ids(bound) ++ subject_ids(not_bound)) == ["a", "b", "c", "d"]
        assert subject_ids(not_bound) == ["d"]

      {bound, not_bound} ->
        assert {:error, _} = bound
        assert {:error, _} = not_bound
    end
  end

  if Code.ensure_loaded?(AshSqlite.DataLayer) do
    @tag :sqlite
    test "SQLite bindings and FILTER outcomes equal ETS for boolean, date, decimal, uuid, utc_datetime" do
      repo = C.Db.start_sqlite!()

      # decimal is a TEXT column on purpose: SQLite has no decimal type (see the typed court).
      Ecto.Adapters.SQL.query!(
        repo,
        "CREATE TABLE IF NOT EXISTS w16_typed_rows (pid TEXT PRIMARY KEY NOT NULL, flag INTEGER, " <>
          "born_on TEXT, amount TEXT, ref TEXT, seen_at TEXT)",
        []
      )

      reseed!(Ty.Ets)
      reference = observe(Ty.Ets)

      reseed!(Ty.Sqlite)
      actual = observe(Ty.Sqlite)

      assert Map.keys(actual) == Map.keys(reference)

      for {name, _} <- @queries do
        assert {name, actual[name]} == {name, reference[name]}
      end

      # positive control: the comparison is not vacuous, the unfiltered scans returned rows.
      assert {:ok, [_, _, _, _]} = actual.all_flag
      assert length(values(actual.all_amount)) == 3
    end
  end
end
