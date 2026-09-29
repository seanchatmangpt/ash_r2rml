# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928ConsumersTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase

  alias AshR2RML.Refusal
  alias AshR2RML.VKG
  alias AshR2RML.VKG.{Executor, Receipt, Session}
  alias AshR2RML.VKG.Consumer.{Engineering, GraphQL}

  defp session(n) do
    {catalog, plan} = plan(["customer"])

    rows =
      for i <- 1..n do
        %{"subject" => "https://example.org/customer/#{i}", "name" => "N#{i}"}
      end

    {:ok, result, obs} =
      Executor.execute(plan,
        engine: AshR2RML.VKGCase.FakeEngine,
        fake_rows: %{"customer" => rows}
      )

    Session.new(catalog, plan, result, obs, Receipt.build(plan, result, obs))
  end

  test "pagination walks pages with correct pageInfo" do
    s = session(3)
    {:ok, p1} = GraphQL.page(s, first: 2)
    assert length(p1["edges"]) == 2
    assert p1["pageInfo"]["hasNextPage"] == true
    assert p1["pageInfo"]["hasPreviousPage"] == false

    {:ok, p2} = GraphQL.page(s, first: 2, after: p1["pageInfo"]["endCursor"])
    assert length(p2["edges"]) == 1
    assert p2["pageInfo"]["hasNextPage"] == false
    assert p2["pageInfo"]["hasPreviousPage"] == true

    all = Enum.map(p1["edges"] ++ p2["edges"], & &1["cursor"])
    assert length(Enum.uniq(all)) == 3
    assert {:ok, ^p1} = GraphQL.page(s, first: 2)
  end

  test "first 0, oversized first, and exact-fit page" do
    s = session(3)

    assert {:ok, %{"edges" => [], "pageInfo" => %{"hasNextPage" => true, "endCursor" => nil}}} =
             GraphQL.page(s, first: 0)

    assert {:ok, %{"edges" => e, "pageInfo" => %{"hasNextPage" => false}}} =
             GraphQL.page(s, first: 100)

    assert length(e) == 3
    assert {:ok, %{"pageInfo" => %{"hasNextPage" => false}}} = GraphQL.page(s, first: 3)
  end

  test "invalid first and cursors are typed refusals" do
    s = session(3)
    {:ok, p} = GraphQL.page(s, first: 1)
    other = session(2)

    for opts <- [
          [first: nil],
          [first: -1],
          [first: "2"],
          [after: "garbage"],
          [after: 5],
          [after: Base.url_encode64("x:1:y", padding: false)],
          [after: p["pageInfo"]["endCursor"] <> "A"],
          [first: 1, after: hd(GraphQL.connection(other, first: 1)["edges"])["cursor"]]
        ] do
      assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = GraphQL.page(s, opts)
    end

    assert {:error, %Refusal{}} = GraphQL.connection(s, first: -1)
    assert {:error, %Refusal{}} = GraphQL.page(s, :bad)
    assert {:error, %Refusal{}} = GraphQL.page(:nope, [])
  end

  test "engineering source_trace edge cases" do
    s = session(2)
    assert Engineering.source_trace(s, "urn:unknown") == []
    assert Engineering.source_trace(s, nil) == []
    assert length(Engineering.subjects(s)) == 2
  end

  test "facade refuses malformed arguments with typed refusals" do
    assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = VKG.query(:customer)
    assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}} = VKG.query("customer", [])
    assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = VKG.query(["customer"], :bad)
    assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = VKG.query(["customer"], [1, 2])
    assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = VKG.query_all(:bad)
    assert {:error, %Refusal{code: :REFUSED_VKG_QUERY_PLAN}} = VKG.catalog(:bad)
  end

  test "query_all uses one catalog and verify/2 binds to catalog" do
    {:ok, s} = VKG.query_all(engine: AshR2RML.VKGCase.FakeEngine)
    {:ok, catalog} = VKG.catalog()
    assert s.catalog_sha256 == catalog.sha256
    assert s.plan.contract_ids == AshR2RML.VKG.Catalog.ids(catalog)
    assert :ok = VKG.verify(s)
    assert :ok = VKG.verify(s, catalog: catalog)
    assert :ok = VKG.verify(s, root: AshR2RML.VKG.Manifest.default_root())

    {:ok, other} = AshR2RML.VKG.Catalog.new([contract("customer")])

    assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY, subject: :catalog}} =
             VKG.verify(s, catalog: other)

    assert {:error, %Refusal{code: :REFUSED_VKG_REPLAY}} = VKG.verify(:nope)
    assert {:error, %Refusal{}} = VKG.verify(s, :bad)
  end

  test "previous_receipt accepts a receipt struct" do
    {:ok, s1} = VKG.query(["customer"], engine: AshR2RML.VKGCase.FakeEngine)
    {:ok, s2} = VKG.query(["customer"], engine: AshR2RML.VKGCase.FakeEngine, previous_receipt: s1.receipt)
    assert s2.receipt.previous == s1.receipt.id
  end
end
