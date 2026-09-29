# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V269282ExecuteTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.OBDA.Observation
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Batch, Executor, Planner}

  defmodule Wrap do
    # Delegates to FakeEngine then mutates the observation via :mutate.
    def execute(stage, opts) do
      {:ok, obs} = AshR2RML.VKGCase.FakeEngine.execute(stage, opts)
      Keyword.fetch!(opts, :mutate).(obs, stage)
    end
  end

  defp run(plan, mutate, extra \\ []) do
    Executor.execute(plan, [engine: Wrap, mutate: mutate] ++ extra)
  end

  test "test-double engine does not claim live standing; evidence_kind is retained" do
    {_c, plan} = plan(["customer"])
    assert {:ok, result, obs} = Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)
    assert result.standing == :test_double_only
    assert obs["customer"].evidence_kind == :injected_runner
  end

  test "self-reported live process evidence from a non-Ontop engine is not promoted" do
    {_c, plan} = plan(["customer"])

    mutate = fn obs, _ ->
      {:ok, %{obs | evidence_kind: :system_process, standing: :observed_not_actuated}}
    end

    assert {:ok, %{standing: :test_double_only}, _} = run(plan, mutate)
  end

  test "non-3-arity runner refuses instead of falling through to live Ontop" do
    {_c, plan} = plan(["customer"])

    assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION} = r} =
             Executor.execute(plan, runner: fn _ -> :nope end)

    assert r.evidence.cause.code == :REFUSED_VKG_EXECUTION
    assert r.evidence.cause.detail =~ "3-arity"
  end

  test "observation digest drift is refused" do
    {_c, plan} = plan(["customer"])
    mutate = fn obs, _ -> {:ok, %{obs | mapping_sha256: String.duplicate("f", 64)}} end
    assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} = run(plan, mutate)

    mutate = fn obs, _ -> {:ok, %{obs | query_sha256: String.duplicate("f", 64)}} end
    assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} = run(plan, mutate)
  end

  test "matching observation digests are accepted" do
    {_c, plan} = plan(["customer"])
    [stage] = plan.stages

    mutate = fn obs, _ ->
      {:ok, %{obs | mapping_sha256: stage.mapping_sha256, query_sha256: stage.query_sha256}}
    end

    assert {:ok, _, _} = run(plan, mutate)
  end

  test "pre-execution file re-hash refuses a swapped mapping file" do
    {_c, plan} = plan(["customer"])

    assert {:error, %Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} =
             Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine, verify_files: true)
  end

  test "malformed engine returns are typed refusals" do
    {_c, plan} = plan(["customer"])

    for bad <- [:ok, nil, {:ok, :not_an_observation}, {:weird, 1}, {:ok, %{rows: []}}] do
      assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} = run(plan, fn _, _ -> bad end)
    end

    assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} =
             run(plan, fn obs, _ -> {:ok, %{obs | rows: :nope}} end)
  end

  test "non-map rows, mismatched row_count and unbounded observations are refused" do
    {_c, plan} = plan(["customer"])

    assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} =
             run(plan, fn obs, _ -> {:ok, %{obs | rows: ["x"], row_count: 1}} end)

    assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} =
             run(plan, fn obs, _ -> {:ok, %{obs | rows: [%URI{}], row_count: 1}} end)

    assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} =
             run(plan, fn obs, _ -> {:ok, %{obs | row_count: 99}} end)

    assert {:error, %Refusal{code: :REFUSED_VKG_EXECUTION}} =
             run(plan, fn obs, _ -> {:ok, %{obs | bounded?: false}} end)
  end

  test "max_rows is enforced before later stages run" do
    catalog = catalog(["customer", "order"])
    assert {:ok, plan} = Planner.plan(catalog, ["customer", "order"], max_rows: 1)
    test_pid = self()

    mutate = fn obs, stage ->
      send(test_pid, {:ran, stage.contract_id})
      {:ok, %{obs | rows: obs.rows ++ obs.rows, row_count: 2}}
    end

    assert {:error, %Refusal{code: :REFUSED_RESOURCE_BOUND}} = run(plan, mutate)
    assert_received {:ran, _first}
    refute_received {:ran, _second}
  end

  describe "by_subject merge" do
    defp merged_result(ids, rows, catalog_ids \\ nil) do
      catalog = catalog(catalog_ids || ids)
      {:ok, plan} = Planner.plan(catalog, ids, merge: :by_subject)
      {:ok, result, _} = Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine, fake_rows: rows)
      result
    end

    test "is deterministic across input order, lossless on conflicts, keeps provenance" do
      rows = %{
        "customer" => [%{"subject" => "urn:s:1", "name" => "Ada", "tier" => "gold"}],
        "order" => [%{"subject" => "urn:s:1", "name" => "Grace", "amount" => "42"}]
      }

      a = merged_result(["customer", "order"], rows)
      b = merged_result(["order", "customer"], rows, ["customer", "order"])

      assert a.rows == b.rows
      assert [row] = a.rows
      assert row["name"] == ["Ada", "Grace"]
      assert row["tier"] == "gold" and row["amount"] == "42"
      meta = row["_vkg"]
      assert meta["federated_sources"] == ["customer", "order"]
      assert length(meta["source_receipts"]) == 2
      assert Enum.all?(meta["source_receipts"], &(byte_size(&1["row_sha256"]) == 64))
      assert is_binary(meta["contract_id"])
      assert a.sources == %{"customer" => 1}
    end

    test "nil-subject rows are kept" do
      rows = %{
        "customer" => [%{"name" => "A"}],
        "order" => [%{"name" => "B"}]
      }

      assert merged_result(["customer", "order"], rows).row_count == 2
    end
  end

  describe "batch" do
    test "is bounded with a typed refusal" do
      requests = for _ <- 1..3, do: %{contracts: []}

      assert %{admitted: [], refused: [%{reason: %Refusal{code: :REFUSED_RESOURCE_BOUND}}]} =
               Batch.run(requests, max_requests: 2)
    end

    test "non-map requests are typed refusals and do not raise" do
      assert %{refused: [%{index: 0, reason: %Refusal{code: :REFUSED_VKG_QUERY_SCOPE}}, %{index: 1}]} =
               Batch.run([:junk, %{}])
    end
  end

  test "Observation struct is what the engine contract expects" do
    assert %Observation{rows: []}.rows == []
  end
end
