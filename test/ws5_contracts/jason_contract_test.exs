defmodule AshR2RML.WS5.JasonContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Jason JSON dependency remains ~> 1.4" do
    assert @manifest =~ ~s({:jason, "~> 1.4"})
  end
end
