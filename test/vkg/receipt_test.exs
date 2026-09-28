defmodule AshR2RML.VKG.ReceiptTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Executor, Receipt}

  test "receipt identity is deterministic and source-bound" do
    {_catalog, plan} = plan(["customer"])
    {:ok, result, observations} = Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)
    first = Receipt.build(plan, result, observations)
    second = Receipt.build(plan, result, observations)
    assert first == second
    assert first.plan_sha256 == plan.sha256
    assert first.result_sha256 == result.sha256
    assert first.authority == :NONE
    assert :ok = Receipt.verify(first, plan, result)
  end

  test "changing an observed result invalidates the receipt" do
    {_catalog, plan} = plan(["customer"])
    {:ok, result, observations} = Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)
    receipt = Receipt.build(plan, result, observations)
    different = AshR2RML.VKG.Result.build(plan.sha256, [%{"subject" => "urn:different"}])

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_REPLAY}} =
             Receipt.verify(receipt, plan, different)
  end
end
