# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928IntegrityReviewTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Executor, Planner, Receipt, Replay, Result, Serializer, Session}

  @engine AshR2RML.VKGCase.FakeEngine

  defp sealed(ids \\ ["customer", "order"]) do
    catalog = catalog(ids)
    {:ok, plan} = Planner.plan(catalog, ids, [])
    {:ok, result, observations} = Executor.execute(plan, engine: @engine)
    receipt = Receipt.build(plan, result, observations)
    {plan, result, observations, receipt, Session.new(catalog, plan, result, observations, receipt)}
  end

  test "H1: result standing flip (test double -> live) must not verify" do
    {plan, result, observations, receipt, session} = sealed()
    assert result.standing == :test_double_only
    forged = %{result | standing: :observed_not_actuated}
    assert {:error, %Refusal{}} = Replay.verify(receipt, plan, forged, observations)
    assert {:error, %Refusal{}} = Session.verify(%{session | result: forged})
  end

  test "H1b: standing flip via result JSON must not verify" do
    {plan, result, _o, receipt, _s} = sealed()

    rjson =
      result
      |> Serializer.encode_result!()
      |> Jason.decode!()
      |> Map.put("standing", "observed_not_actuated")
      |> Jason.encode!()

    assert {:error, %Refusal{}} = Serializer.verify_receipt_json(Serializer.encode_receipt!(receipt), rjson, plan)
  end

  test "H2: receipt standing must agree with the test-double result standing" do
    {plan, result, observations, receipt, _s} = sealed()
    assert result.standing == :test_double_only
    refute receipt.standing == :observed_not_actuated
    assert :ok = Replay.verify(receipt, plan, result, observations)
  end

  test "H3: observation evidence_kind flip (injected -> system_process) must not verify" do
    {_plan, _result, observations, _receipt, session} = sealed()

    forged =
      Map.new(observations, fn {id, o} ->
        {id, %{o | evidence_kind: :system_process, standing: :observed_not_actuated}}
      end)

    assert {:error, %Refusal{}} = Session.verify(%{session | observations: forged})
  end

  test "H3b: arbitrary observation metadata mutation must not verify" do
    {_plan, _result, observations, _receipt, session} = sealed()

    forged =
      Map.new(observations, fn {id, o} -> {id, %{o | output_sha256: "deadbeef", system: :evil, duration_ms: 999}} end)

    assert {:error, %Refusal{}} = Session.verify(%{session | observations: forged})
  end

  test "H4: float row_count (2.0 == 2) on result must not verify" do
    {plan, result, observations, receipt, _s} = sealed()
    forged = %{result | row_count: result.row_count * 1.0}
    assert {:error, %Refusal{}} = Replay.verify(receipt, plan, forged, observations)
  end

  test "H5: value type confusion (tuple vs map, atom vs string) changes rows but keeps digest" do
    plan_sha = String.duplicate("a", 64)
    a = Result.build(plan_sha, [%{"subject" => "s", "v" => {1, 2}}])
    forged = %{a | rows: [%{"subject" => "s", "v" => %{"$tuple" => [1, 2]}}]}
    assert {:error, %Refusal{}} = Result.verify(forged)

    b = Result.build(plan_sha, [%{"subject" => "s", "v" => "ok"}])
    forged_b = %{b | rows: [%{"subject" => "s", "v" => :ok}]}
    assert {:error, %Refusal{}} = Result.verify(forged_b)
  end
end
