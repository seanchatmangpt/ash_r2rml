defmodule AshR2RML.WS5.CryptoRuntimeContractTest do
  use ExUnit.Case, async: true

  test "crypto is a runtime application of ash_r2rml and hashing works" do
    {:ok, applications} = :application.get_key(:ash_r2rml, :applications)
    assert :crypto in applications

    digest = :crypto.hash(:sha256, "ash_r2rml")
    assert byte_size(digest) == 32
    assert Base.encode16(digest, case: :lower) =~ ~r/\A[0-9a-f]{64}\z/
  end
end
