defmodule AshR2RML.VKG.IntegrationTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG
  alias AshR2RML.VKG.{Serializer, Session}
  alias AshR2RML.VKG.Consumer.{Engineering, GraphQL}

  test "manifest to plan to execution to consumer to replay closes" do
    rows=%{
      "customer"=>[
        %{"subject"=>"https://example.org/customer/1","name"=>"Ada"},
        %{"subject"=>"https://example.org/customer/2","name"=>"Grace"}
      ],
      "order"=>[
        %{"subject"=>"https://example.org/order/10","customer"=>"https://example.org/customer/1","amount"=>"42"}
      ]
    }

    assert {:ok,%Session{}=session}=
      VKG.query(["customer","order"],engine: AshR2RML.VKGCase.FakeEngine,fake_rows:rows,merge: :union)

    assert :ok=Session.verify(session)
    assert session.result.row_count==3
    assert session.result.sources==%{"customer"=>2,"order"=>1}
    assert session.receipt.contract_ids==["customer","order"]
    assert session.receipt.authority==:NONE

    engineering=Engineering.snapshot(session)
    assert engineering["row_count"]==3
    assert engineering["authority"]=="NONE"

    graphql=GraphQL.connection(session,first:2)
    assert length(graphql["edges"])==2
    assert graphql["receiptId"]==session.receipt.id

    json=Serializer.encode_session!(session)
    assert Jason.decode!(json)["receipt"]["id"]==session.receipt.id
  end

  test "unknown source refuses before any engine call" do
    assert {:error,%AshR2RML.Refusal{}}=
      VKG.query(["customer","does-not-exist"],engine: AshR2RML.VKGCase.FakeEngine)
  end
end
