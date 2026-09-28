defmodule AshR2RML.VKG.SerializerMetricsTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Executor, Metrics, Receipt, Serializer, Session}

  setup do
    {catalog,plan}=plan(["customer","order"])
    {:ok,result,observations}=Executor.execute(plan,engine: AshR2RML.VKGCase.FakeEngine)
    receipt=Receipt.build(plan,result,observations)
    {:ok,session: Session.new(catalog,plan,result,observations,receipt)}
  end

  test "receipt JSON is deterministic",%{session:s} do
    first=Serializer.encode_receipt!(s.receipt)
    second=Serializer.encode_receipt!(s.receipt)
    assert first==second
    decoded=Jason.decode!(first)
    assert decoded["id"]==s.receipt.id
    assert decoded["authority"]=="NONE"
  end

  test "session serialization preserves result identity",%{session:s} do
    decoded=s |> Serializer.encode_session!() |> Jason.decode!()
    assert decoded["result"]["sha256"]==s.result.sha256
    assert decoded["receipt"]["result_sha256"]==s.result.sha256
  end

  test "metrics report observed source and replay counts",%{session:s} do
    metrics=Metrics.from_session(s)
    assert metrics.contract_count==2
    assert metrics.observed_contract_count==2
    assert metrics.row_count==2
    assert metrics.replay_verifiable?
  end
end
