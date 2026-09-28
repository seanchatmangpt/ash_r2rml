defmodule AshR2RML.VKG.PlannerTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Planner, QueryPlan}

  test "plan preserves requested source order and exact digests" do
    catalog=catalog(["customer","order"])
    assert {:ok,plan}=Planner.plan(catalog,["order","customer"],max_rows:123,timeout_ms:456)
    assert plan.contract_ids==["order","customer"]
    assert Enum.map(plan.stages,& &1.contract_id)==["order","customer"]
    assert plan.max_rows==123
    assert plan.timeout_ms==456
    assert :ok=QueryPlan.verify(plan)
  end

  test "capability mismatch refuses before execution" do
    {:ok,catalog}=AshR2RML.VKG.Catalog.new([contract("asset",capabilities:[:select])])
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_CAPABILITY}}=Planner.plan(catalog,["asset"],capability: :join)
  end

  test "tampered plan digest fails replay admission" do
    {_catalog,plan}=plan(["customer"])
    tampered=%{plan|sha256:String.duplicate("0",64)}
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_QUERY_PLAN}}=QueryPlan.verify(tampered)
  end
end
