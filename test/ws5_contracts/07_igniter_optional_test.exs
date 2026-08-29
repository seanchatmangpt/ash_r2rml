defmodule AshR2RML.WS5.IgniterOptionalTest do
  use ExUnit.Case, async: true

  test "Igniter remains an optional production extension" do
    mix = File.read!("mix.exs")
    assert mix =~ ~s({:igniter, ">= 0.6.29 and < 1.0.0-0")
    assert mix =~ "optional: true"
  end
end
