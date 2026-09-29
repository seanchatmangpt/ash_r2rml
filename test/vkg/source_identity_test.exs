defmodule AshR2RML.VKG.SourceIdentityTest do
  use ExUnit.Case, async: true
  alias AshR2RML.VKG.SourceIdentity

  test "descriptor identity is deterministic and exact" do
    attrs = %{
      id: "customer",
      uri: "urn:source:customer",
      graph: "urn:graph:customer",
      subject_template: "https://example.org/customer/{id}",
      version: "1"
    }

    assert {:ok, first} = SourceIdentity.new(attrs)
    assert {:ok, second} = SourceIdentity.new(attrs)
    assert first == second
    assert byte_size(first.sha256) == 64
    assert :ok = SourceIdentity.verify(first, first.sha256)
  end

  test "source descriptor drift is refused" do
    {:ok, identity} =
      SourceIdentity.new(%{
        id: "customer",
        uri: "urn:source:customer",
        graph: "urn:graph:customer",
        subject_template: "x",
        version: "1"
      })

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_SOURCE_DRIFT}} =
             SourceIdentity.verify(identity, String.duplicate("0", 64))
  end

  test "relative source identifiers are not silently admitted" do
    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_SOURCE_IDENTITY}} =
             SourceIdentity.new(%{
               id: "x",
               uri: "db/customer",
               graph: "urn:g",
               subject_template: "x"
             })
  end
end
