defmodule AshR2RML.WS5.JSONLDContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "JSON-LD interchange dependency remains ~> 1.0.1" do
    assert @manifest =~ ~s({:json_ld, "~> 1.0.1"})
  end
end
