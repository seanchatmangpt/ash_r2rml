defmodule AshR2RML.WS5.AshFloorTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Ash remains on the admitted 3.x floor with >= 3.28.0" do
    assert @manifest =~ ~s({:ash, "~> 3.0 and >= 3.28.0"})
  end
end
