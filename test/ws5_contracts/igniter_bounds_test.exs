defmodule AshR2RML.WS5.IgniterBoundsTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Igniter remains optional and bounded below 1.0" do
    assert @manifest =~ ">= 0.6.29 and < 1.0.0-0"
    assert @manifest =~ "optional: true"
  end
end
