defmodule AshR2RML.VKG.ContractTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.Contract
  @digest String.duplicate("a",64)
  test "admits exact source and mapping identity" do
    c=%Contract{id: "customer",source:"urn:source:customer",graph:"urn:graph:customer",source_sha256:@digest,mapping_sha256:@digest,subject_template:"https://example.org/customer/{id}"}
    assert {:ok,^c}=Contract.admit(c)
  end
  test "refuses source drift" do
    c=%Contract{id:"customer",source:"urn:source:customer",graph:"urn:graph:customer",source_sha256:"drift",mapping_sha256:@digest,subject_template:"x"}
    assert {:error,:REFUSED_VKG_CONTRACT_IDENTITY}=Contract.admit(c)
  end
end
