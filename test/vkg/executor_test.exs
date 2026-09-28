defmodule AshR2RML.VKG.ExecutorTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Executor, Provenance}

  test "federated execution preserves per-row exact source provenance" do
    {_catalog, plan} = plan(["customer", "order"])

    rows = %{
      "customer" => [%{"subject" => "urn:c:1", "name" => "Ada"}],
      "order" => [%{"subject" => "urn:o:9", "amount" => "42"}]
    }

    assert {:ok, result, observations} =
             Executor.execute(
               plan,
               engine: AshR2RML.VKGCase.FakeEngine,
               fake_rows: rows
             )

    assert result.row_count == 2
    assert map_size(observations) == 2

    for stage <- plan.stages do
      row =
        Enum.find(
          result.rows,
          &(get_in(&1, ["_vkg", "contract_id"]) == stage.contract_id)
        )

      assert Provenance.exact_source?(row, stage)
    end
  end

  test "one refused stage refuses the exact requested federation" do
    {_catalog, plan} = plan(["customer", "order"])

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_EXECUTION}} =
             Executor.execute(plan, engine: AshR2RML.VKGCase.RefusingEngine)
  end

  test "global result bound is enforced after federation" do
    {_catalog, plan0} = plan(["customer", "order"])
    plan = %{plan0 | max_rows: 1}

    rows = %{
      "customer" => [%{"subject" => "urn:c:1"}],
      "order" => [%{"subject" => "urn:o:1"}]
    }

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_RESOURCE_BOUND}} =
             Executor.execute(
               plan,
               engine: AshR2RML.VKGCase.FakeEngine,
               fake_rows: rows
             )
  end
end
