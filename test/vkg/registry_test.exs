defmodule AshR2RML.VKG.RegistryTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.{Contract,Registry}
  @digest String.duplicate("b",64)
  defp c(id), do: %Contract{id:id,source:"urn:source:"<>id,graph:"urn:graph:"<>id,source_sha256:@digest,mapping_sha256:@digest,subject_template:"https://example.org/"<>id<>"/{id}"}
  test "registry preserves exact identities" do
    assert {:ok,r}=Registry.admit([c("a"),c("b")]); assert map_size(r)==2
  end
  test "duplicate subject identity is refused" do
    assert {:error,:REFUSED_VKG_REGISTRY_AMBIGUOUS}=Registry.admit([c("a"),c("a")])
  end
end
