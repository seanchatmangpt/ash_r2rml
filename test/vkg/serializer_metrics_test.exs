defmodule AshR2RML.VKG.SerializerMetricsTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Executor, Metrics, Receipt, Serializer, Session}

  setup do
    {catalog, plan} = plan(["customer", "order"])

    {:ok, result, observations} =
      Executor.execute(plan, engine: AshR2RML.VKGCase.FakeEngine)

    receipt = Receipt.build(plan, result, observations)
    {:ok, session: Session.new(catalog, plan, result, observations, receipt)}
  end

  test "receipt JSON is deterministic", %{session: session} do
    first = Serializer.encode_receipt!(session.receipt)
    second = Serializer.encode_receipt!(session.receipt)

    assert first == second

    decoded = Jason.decode!(first)
    assert decoded["id"] == session.receipt.id
    assert decoded["authority"] == "NONE"
  end

  test "session serialization preserves result identity", %{session: session} do
    decoded =
      session
      |> Serializer.encode_session!()
      |> Jason.decode!()

    assert decoded["result"]["sha256"] == session.result.sha256
    assert decoded["receipt"]["result_sha256"] == session.result.sha256
  end

  test "metrics report observed source and replay counts", %{session: session} do
    metrics = Metrics.from_session(session)

    assert metrics.contract_count == 2
    assert metrics.observed_contract_count == 2
    assert metrics.row_count == 2
    assert metrics.replay_verifiable?
  end
end
