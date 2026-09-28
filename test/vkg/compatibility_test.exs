defmodule AshR2RML.VKG.CompatibilityTest do
  use ExUnit.Case, async: true

  import AshR2RML.VKGCase
  alias AshR2RML.VKG.Compatibility

  test "same-version observe-only contracts compose" do
    contracts = [contract("customer"), contract("order")]

    assert :ok = Compatibility.check(contracts)
    assert Enum.all?(Compatibility.matrix(contracts), & &1.compatible?)
  end

  test "graph identity collision is refused" do
    left = contract("left", graph: "urn:graph:shared")
    right = contract("right", graph: "urn:graph:shared")

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_COMPATIBILITY}} =
             Compatibility.check([left, right])
  end

  test "mixed contract versions are refused" do
    left = contract("left")
    right = %{contract("right") | version: "2"}

    assert {:error, %AshR2RML.Refusal{code: :REFUSED_VKG_COMPATIBILITY}} =
             Compatibility.check([left, right])
  end
end
