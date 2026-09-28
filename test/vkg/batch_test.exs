defmodule AshR2RML.VKG.BatchTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.Batch

  test "independent requests preserve admitted results when another request is refused" do
    requests=[
      %{contracts:["customer"]},
      %{contracts:["missing"]},
      %{contracts:["order"]}
    ]
    result=Batch.run(requests,engine: AshR2RML.VKGCase.FakeEngine)
    assert Enum.map(result.admitted,& &1.index)==[0,2]
    assert [%{index:1,reason:%AshR2RML.Refusal{}}]=result.refused
  end

  test "batch preserves request order inside admitted and refused lanes" do
    requests=for id <- ~w(customer order product), do: %{contracts:[id]}
    result=Batch.run(requests,engine: AshR2RML.VKGCase.FakeEngine)
    assert Enum.map(result.admitted,& &1.index)==[0,1,2]
    assert result.refused==[]
  end
end
