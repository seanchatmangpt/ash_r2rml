defmodule AshR2RML.VKG.DeterminismTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG

  test "equivalent engine row order yields one result identity" do
    rows_a=%{"customer"=>[
      %{"subject"=>"urn:c:2","name"=>"Grace"},
      %{"subject"=>"urn:c:1","name"=>"Ada"}
    ]}
    rows_b=%{"customer"=>Enum.reverse(rows_a["customer"])}

    assert {:ok,left}=VKG.query(["customer"],engine: AshR2RML.VKGCase.FakeEngine,fake_rows:rows_a)
    assert {:ok,right}=VKG.query(["customer"],engine: AshR2RML.VKGCase.FakeEngine,fake_rows:rows_b)

    assert left.plan.sha256==right.plan.sha256
    assert left.result.sha256==right.result.sha256
    assert left.result.rows==right.result.rows
  end

  test "a semantic row change changes result and receipt identity" do
    assert {:ok,left}=VKG.query(["customer"],engine: AshR2RML.VKGCase.FakeEngine,
      fake_rows:%{"customer"=>[%{"subject"=>"urn:c:1","name"=>"Ada"}]})
    assert {:ok,right}=VKG.query(["customer"],engine: AshR2RML.VKGCase.FakeEngine,
      fake_rows:%{"customer"=>[%{"subject"=>"urn:c:1","name"=>"Changed"}]})

    refute left.result.sha256==right.result.sha256
    refute left.receipt.id==right.receipt.id
  end
end
