defmodule AshR2RML.WS5.ReactorOptionalContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "Reactor saga integration remains optional to the semantic compiler" do
    assert @mix =~ ~s({:reactor, ">= 0.9.0", optional: true})
  end
end
