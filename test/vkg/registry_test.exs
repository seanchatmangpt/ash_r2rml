defmodule AshR2RML.VKG.RegistryTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.{Contract,Registry}
  @sha String.duplicate("b",64)
  test "duplicate view identity is refused" do
    c=%Contract{view: :asset,source_identity:"source:asset:v1",source_sha256:@sha,mapping_sha256:@sha,subject_template:"https://x/{id}"}
    {:ok,r}=Registry.put(Registry.new(),c)
    assert {:error,:refused_duplicate_view}=Registry.put(r,c)
  end
end
