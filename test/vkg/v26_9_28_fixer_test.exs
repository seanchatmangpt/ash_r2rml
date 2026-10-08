# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928FixerTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.OBDA.Observation
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Contract, Executor, Planner, QueryPlan, Receipt, Replay, Result, Serializer, Session}

  @fake AshR2RML.VKGCase.FakeEngine

  defmodule ForgingEngine do
    def execute(stage, opts) do
      {:ok, obs} = AshR2RML.VKGCase.FakeEngine.execute(stage, opts)
      {:ok, %Observation{obs | evidence_kind: :system_process, standing: :obda_query_observed}}
    end
  end

  defmodule RaisingEngine do
    def execute(_stage, _opts), do: raise("boom")
  end

  defmodule ThrowingEngine do
    def execute(_stage, _opts), do: throw(:nope)
  end

  defp sealed(engine \\ @fake, opts \\ []) do
    catalog = catalog(["customer", "order"])
    {:ok, plan} = Planner.plan(catalog, ["customer", "order"], [])
    {:ok, result, obs} = Executor.execute(plan, [engine: engine] ++ opts)
    receipt = Receipt.build(plan, result, obs)
    {plan, result, obs, receipt, Session.new(catalog, plan, result, obs, receipt)}
  end

  defp live_run(tmp_dir) do
    bin = Path.join(tmp_dir, "fakeontop")
    File.write!(bin, "#!/bin/sh\nprintf 'subject,name\\nhttp://x/1,A\\n'\n")
    File.chmod!(bin, 0o755)
    {_c, plan} = plan(["customer"])
    {plan, Executor.execute(plan, binary: bin, verify_files: false)}
  end

  describe "standing is bound" do
    test "result standing is part of the digest and flips are refused everywhere" do
      {plan, result, obs, receipt, session} = sealed()
      assert result.standing == :test_double_only
      forged = %{result | standing: :observed_not_actuated}

      assert {:error, %Refusal{subject: :result}} = Result.verify(forged)
      assert {:error, %Refusal{}} = Replay.verify(receipt, plan, forged, obs)
      assert {:error, %Refusal{}} = Session.verify(%{session | result: forged})

      rjson =
        result
        |> Serializer.encode_result!()
        |> Jason.decode!()
        |> Map.put("standing", "observed_not_actuated")
        |> Jason.encode!()

      assert {:error, %Refusal{}} =
               Serializer.verify_receipt_json(Serializer.encode_receipt!(receipt), rjson, plan)

      assert :ok = Session.verify(session)
    end

    test "receipt standing derives from the result and must agree with it" do
      {plan, result, obs, receipt, _s} = sealed()
      assert receipt.standing == :test_double_only
      assert :ok = Replay.verify(receipt, plan, result, obs)

      # receipt re-sealed with a live claim over a test-double result
      lying = %{receipt | standing: :observed_not_actuated}
      lying = %{lying | sha256: Receipt.compute_sha256(lying)}
      lying = %{lying | id: "vkg-receipt-" <> binary_part(lying.sha256, 0, 20)}
      assert {:error, %Refusal{subject: :standing}} = Replay.verify(lying, plan, result, obs)

      json = Serializer.encode_receipt!(receipt)
      assert {:ok, %Receipt{standing: :test_double_only} = decoded} = Serializer.decode_receipt(json)
      assert decoded == receipt
    end

    test "observation evidence and metadata are digest-bound in Session.verify" do
      {_p, _r, obs, _rc, session} = sealed()

      flipped =
        Map.new(obs, fn {id, o} -> {id, %{o | evidence_kind: :system_process, standing: :obda_query_observed}} end)

      assert {:error, %Refusal{subject: :observations}} = Session.verify(%{session | observations: flipped})

      meta = Map.new(obs, fn {id, o} -> {id, %{o | output_sha256: "deadbeef", system: :evil, duration_ms: 999}} end)
      assert {:error, %Refusal{subject: :observations}} = Session.verify(%{session | observations: meta})
    end

    test "float row_count is refused on result and receipt" do
      {plan, result, obs, receipt, _s} = sealed()
      forged = %{result | row_count: result.row_count * 1.0}
      assert {:error, %Refusal{subject: :row_count}} = Result.verify(forged)
      assert {:error, %Refusal{}} = Replay.verify(receipt, plan, forged, obs)

      json = result |> Serializer.encode_result!() |> String.replace("\"row_count\":2", "\"row_count\":2.0")
      assert {:ok, decoded} = Serializer.decode_result(json)
      assert {:error, %Refusal{}} = Result.verify(decoded)
    end
  end

  describe "canonical digest is injective over sealed rows" do
    test "tuple vs $tuple map, atom vs string, date/decimal vs string are distinguishable" do
      plan_sha = String.duplicate("a", 64)
      sealed_map = Result.build(plan_sha, [%{"subject" => "s", "v" => %{"$tuple" => [1, 2]}}])
      assert :ok = Result.verify(sealed_map)
      tuple = Result.build(plan_sha, [%{"subject" => "s", "v" => {1, 2}}])
      refute tuple.sha256 == sealed_map.sha256
      assert tuple.rows == [%{"subject" => "s", "v" => [1, 2]}]

      for {typed, string} <- [{:ok, "ok"}, {~D[2026-09-28], "2026-09-28"}, {Decimal.new("1.5"), "1.5"}] do
        a = Result.build(plan_sha, [%{"subject" => "s", "v" => string}])
        forged = %{a | rows: [%{"subject" => "s", "v" => typed}]}
        assert {:error, %Refusal{subject: :rows}} = Result.verify(forged)
        # sealing normalizes to the JSON-native form, so it verifies and matches
        assert Result.build(plan_sha, [%{"subject" => "s", "v" => typed}]).sha256 == a.sha256
      end
    end

    test "canonical JSON never lets data spell a reserved tag" do
      refute Serializer.canonical_json({1, 2}) == Serializer.canonical_json(%{"$tuple" => [1, 2]})
      refute Serializer.canonical_json(%{"$binary" => "AA=="}) == Serializer.canonical_json(<<255>>)
    end
  end

  describe "live standing authority" do
    test "a forging engine module cannot self-assert live standing" do
      {_p, result, _o, receipt, _s} = sealed(ForgingEngine)
      assert result.standing == :test_double_only
      assert receipt.standing == :test_double_only
    end

    @tag :tmp_dir
    test "a genuine Ontop system-process observation yields live standing", %{tmp_dir: tmp_dir} do
      {plan, {:ok, result, obs}} = live_run(tmp_dir)
      assert [%Observation{evidence_kind: :system_process, standing: :obda_query_observed}] = Map.values(obs)
      assert result.standing == :observed_not_actuated

      receipt = Receipt.build(plan, result, obs)
      assert receipt.standing == :observed_not_actuated
      assert :ok = Replay.verify(receipt, plan, result, obs)
      assert {:ok, rebuilt} = Replay.reconstruct(plan, obs)
      assert rebuilt.sha256 == result.sha256

      # downgrading the recorded evidence breaks the receipt
      down = Map.new(obs, fn {id, o} -> {id, %{o | evidence_kind: :injected_runner}} end)
      assert {:error, %Refusal{}} = Replay.verify(receipt, plan, result, down)
    end

    test "an injected runner through the Ontop engine is never live" do
      {_c, plan} = plan(["customer"])

      runner = fn _cmd, _args, _opts -> {"subject,name\nhttp://x/1,A\n", 0} end
      assert {:ok, result, _} = Executor.execute(plan, runner: runner, verify_files: false)
      assert result.standing == :test_double_only
    end
  end

  describe "typed refusals for bad engines and plans" do
    test "non-module engines are refused, not raised" do
      {_c, plan} = plan()

      for engine <- [:not_a_module, nil, "x", 42, Enum] do
        assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION, subject: :engine}} =
                 Executor.execute(plan, engine: engine)
      end
    end

    test "engines that raise or throw are refused" do
      {_c, plan} = plan()

      for engine <- [RaisingEngine, ThrowingEngine] do
        assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} = Executor.execute(plan, engine: engine)
      end
    end

    test "stage capabilities outside the allowlist are refused by new and verify" do
      {_c, plan} = plan()
      stages = Enum.map(plan.stages, &Map.put(&1, :capabilities, [:write, :delete]))

      assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} =
               QueryPlan.new(plan.catalog_sha256, plan.contract_ids, stages)

      assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} = QueryPlan.verify(%{plan | stages: stages})

      assert {:error, %Refusal{code: :REFUSED_VKG_CAPABILITY}} =
               Executor.execute(%{plan | stages: stages}, engine: @fake)

      ok = Enum.map(plan.stages, &Map.put(&1, :capabilities, Contract.capability_allowlist()))
      assert {:ok, _} = QueryPlan.new(plan.catalog_sha256, plan.contract_ids, ok)
    end
  end
end
