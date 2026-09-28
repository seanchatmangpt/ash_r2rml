defmodule AshR2RML.VKG.ConsumerTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Executor, Receipt, Session}
  alias AshR2RML.VKG.Consumer.{Engineering, GraphQL}

  setup do
    {catalog,plan}=plan(["customer"])
    {:ok,result,observations}=Executor.execute(plan,engine: AshR2RML.VKGCase.FakeEngine)
    receipt=Receipt.build(plan,result,observations)
    {:ok,session: Session.new(catalog,plan,result,observations,receipt)}
  end

  test "engineering snapshot retains receipt and source trace",%{session:s} do
    snapshot=Engineering.snapshot(s)
    assert snapshot["authority"]=="NONE"
    assert snapshot["receipt_id"]==s.receipt.id
    assert snapshot["entity_count"]==1
    [subject]=Engineering.subjects(s)
    assert [%{"contract_id"=>"customer"}]=Engineering.source_trace(s,subject)
  end

  test "GraphQL connection is read-only and provenance-bearing",%{session:s} do
    conn=GraphQL.connection(s,first:1)
    assert conn["authority"]=="NONE"
    assert conn["receiptId"]==s.receipt.id
    assert [%{"node"=>node,"provenance"=>provenance,"cursor"=>cursor}]=conn["edges"]
    assert is_map(node)
    assert provenance["contract_id"]=="customer"
    assert is_binary(cursor)
  end
end
