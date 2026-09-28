defmodule AshR2RML.VKG.RegistryTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.Registry

  test "registry preserves exact identities and stable digest" do
    a=contract("a")
    b=contract("b")
    assert {:ok,left}=Registry.admit([a,b])
    assert {:ok,right}=Registry.admit([b,a])
    assert map_size(left)==2
    assert Registry.digest(left)==Registry.digest(right)
  end

  test "duplicate subject identity is refused" do
    a=contract("a")
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}}=Registry.admit([a,a])
  end

  test "unknown contract fetch is a typed refusal" do
    {:ok,registry}=Registry.admit([contract("a")])
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}}=Registry.fetch(registry,"missing")
  end
end
