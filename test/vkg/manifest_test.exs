defmodule AshR2RML.VKG.ManifestTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.Manifest

  test "loads all canonical source manifests and binds artifact bytes" do
    assert {:ok,contracts}=Manifest.load_all()
    assert length(contracts)==10
    assert Enum.map(contracts,& &1.id)==~w(asset customer document event invoice order organization product project service)

    for contract <- contracts do
      assert File.regular?(contract.mapping_path)
      assert File.regular?(contract.query_path)
      assert byte_size(contract.source_sha256)==64
      assert byte_size(contract.mapping_sha256)==64
      assert byte_size(contract.query_sha256)==64
      assert contract.authority==:NONE
    end
  end

  test "manifest snapshot contains provenance identities but no authority" do
    assert {:ok,contract}=Manifest.load(Path.join(Manifest.default_root(),"sources/customer.json"))
    snapshot=Manifest.snapshot(contract)
    assert snapshot.id=="customer"
    assert snapshot.source=="urn:source:customer"
    assert snapshot.graph=="urn:graph:customer"
    refute Map.has_key?(snapshot,:authority)
  end
end
