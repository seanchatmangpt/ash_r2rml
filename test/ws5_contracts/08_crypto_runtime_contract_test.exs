defmodule AshR2RML.WS5.CryptoRuntimeContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "receipt hashing support keeps crypto in runtime applications" do
    assert @mix =~ "extra_applications: [:logger, :crypto]"
  end
end
