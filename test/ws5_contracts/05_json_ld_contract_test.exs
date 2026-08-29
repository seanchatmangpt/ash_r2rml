defmodule AshR2RML.WS5.JsonLdContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "JSON-LD ingestion keeps the 1.0.1 compatibility contract" do
    assert @mix =~ ~s({:json_ld, "~> 1.0.1"})
  end
end
