defmodule AshR2RML.VKG.CatalogTest do
  use ExUnit.Case, async: true
  import AshR2RML.VKGCase
  alias AshR2RML.VKG.{Catalog, Registry}

  test "catalog digest is independent of input ordering" do
    a=contract("customer")
    b=contract("order")
    assert {:ok,left}=Catalog.new([a,b])
    assert {:ok,right}=Catalog.new([b,a])
    assert left.sha256==right.sha256
    assert Catalog.ids(left)==["customer","order"]
  end

  test "duplicate exact subject identifiers refuse registry admission" do
    c=contract("customer")
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}}=Registry.admit([c,c])
  end

  test "select refuses unknown source instead of dropping it" do
    catalog=catalog(["customer"])
    assert {:error,%AshR2RML.Refusal{code: :REFUSED_VKG_REGISTRY_AMBIGUOUS}}=Catalog.select(catalog,["customer","missing"])
  end
end
