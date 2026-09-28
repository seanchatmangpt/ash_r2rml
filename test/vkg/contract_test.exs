defmodule AshR2RML.VKG.ContractTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.Contract
  @sha String.duplicate("a", 64)
  test "admits exact immutable identity and no authority" do
    c=%Contract{view: :customer,source_identity:"source:customer:v1",source_sha256:@sha,mapping_sha256:@sha,subject_template:"https://x/{id}"}
    assert {:ok, ^c}=Contract.admit(c)
  end
  test "refuses source drift" do
    c=%Contract{view: :customer,source_identity:"source:customer:mutable",source_sha256:@sha,mapping_sha256:@sha,subject_template:"https://x/{id}"}
    assert {:error,:refused_vkg_contract}=Contract.admit(c)
  end
end
