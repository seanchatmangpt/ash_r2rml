defmodule AshR2RML.VKG.ContractTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.Contract

  test "admits exact source, mapping and query identity" do
    contract=contract("customer")
    assert {:ok,^contract}=Contract.admit(contract)
    assert Contract.exact_subject?(contract,"customer")
    refute Contract.exact_subject?(contract,"order")
    assert byte_size(Contract.digest(contract))==64
  end

  test "refuses source descriptor drift" do
    contract=contract("customer")
    drifted=%{contract|source_sha256:String.duplicate("0",64)}
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}}=Contract.admit(drifted)
  end

  test "refuses authority escalation" do
    contract=%{contract("customer")|authority: :write}
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_AUTHORITY_ESCALATION}}=Contract.admit(contract)
  end
end
