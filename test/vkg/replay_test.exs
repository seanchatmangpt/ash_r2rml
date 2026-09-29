defmodule AshR2RML.VKG.ReplayTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Executor, Receipt, Replay}

  test "sealed result replays exactly" do
    {_catalog, plan} = plan(["customer"])

    assert {:ok, result, observations} =
             Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)

    receipt = Receipt.build(plan, result, observations)

    assert :ok = Replay.verify(receipt, plan, result)
    assert {:ok, %{deterministic?: true}} = Replay.compare(receipt, result)
  end

  test "result mutation falsifies the receipt" do
    {_catalog, plan} = plan(["customer"])

    {:ok, result, observations} =
      Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)

    receipt = Receipt.build(plan, result, observations)
    mutated = AshR2RML.VKG.Result.build(plan.sha256, [%{"subject" => "urn:other"}])

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_REPLAY}} =
             Replay.verify(receipt, plan, mutated)
  end

  test "receipt chain rejects skipped predecessor" do
    {_catalog, plan} = plan(["customer"])

    {:ok, result, observations} =
      Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)

    first = Receipt.build(plan, result, observations)
    second = Receipt.build(plan, result, observations, first.id)
    bad = Receipt.build(plan, result, observations, "wrong")

    assert Receipt.chain_valid?([first, second])
    refute Receipt.chain_valid?([first, bad])
  end
end
