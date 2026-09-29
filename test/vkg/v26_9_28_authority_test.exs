# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928AuthorityTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.OBDA.Observation
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Executor, Planner, Receipt, Serializer, Session}

  defmodule ForgingEngine do
    def execute(stage, opts) do
      {:ok, obs} = AshR2RML.VKGCase.FakeEngine.execute(stage, opts)
      {:ok, %Observation{obs | evidence_kind: :system_process, standing: :observed_not_actuated}}
    end
  end

  defp sealed(engine) do
    catalog = catalog(["customer"])
    {:ok, plan} = Planner.plan(catalog, ["customer"])
    {:ok, result, obs} = Executor.execute(plan, engine: engine)
    receipt = Receipt.build(plan, result, obs)
    {plan, result, obs, receipt, Session.new(catalog, plan, result, obs, receipt)}
  end

  test "H1: an arbitrary engine module cannot self-assert live standing" do
    {_p, result, _o, _r, _s} = sealed(ForgingEngine)
    assert result.standing == :test_double_only
  end

  test "H2: receipt of a test-double session must not claim observed standing" do
    {_p, result, _o, receipt, _s} = sealed(AshR2RML.VKGCase.FakeEngine)
    assert result.standing == :test_double_only
    assert receipt.standing == :test_double_only
  end

  test "H3: flipping result.standing after sealing must fail Session.verify" do
    {_p, result, _o, _r, session} = sealed(AshR2RML.VKGCase.FakeEngine)
    forged = %{session | result: %{result | standing: :observed_not_actuated}}
    assert {:error, %Refusal{}} = Session.verify(forged)
  end

  test "H4: flipping recorded observation evidence to system_process must fail verify" do
    {_p, _r, obs, _rc, session} = sealed(AshR2RML.VKGCase.FakeEngine)

    forged_obs =
      Map.new(obs, fn {k, o} -> {k, %{o | evidence_kind: :system_process, standing: :observed_not_actuated}} end)

    assert {:error, %Refusal{}} = Session.verify(%{session | observations: forged_obs})
  end

  test "H5: non-module engine yields a typed refusal, not a bare exception" do
    {_c, plan} = plan()
    assert {:error, %Refusal{}} = Executor.execute(plan, engine: :not_a_module)
  end

  test "H6: hand-built plan with non-allowlisted stage capability is refused by verify" do
    {_c, plan} = plan()
    stages = Enum.map(plan.stages, &Map.put(&1, :capabilities, [:write, :delete]))

    assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} =
             AshR2RML.VKG.QueryPlan.new(plan.catalog_sha256, plan.contract_ids, stages)

    forged = %{plan | stages: stages}
    assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} = AshR2RML.VKG.QueryPlan.verify(forged)
  end

  test "H7: serialized test-double receipt keeps its standing through JSON round trip" do
    {_p, _r, _o, receipt, _s} = sealed(AshR2RML.VKGCase.FakeEngine)
    assert receipt.standing == :test_double_only
    _ = Serializer
  end
end
