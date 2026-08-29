defmodule AshR2RML.WS5.IgniterOptionalContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "Igniter remains an optional bounded consumer integration" do
    assert @mix =~ ~s({:igniter, ">= 0.6.29 and < 1.0.0-0", [env: :prod, hex: "igniter", repo: "hexpm", optional: true]})
  end
end
