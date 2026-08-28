defmodule AshR2RML.WS5.AshDependencyTest do
  use ExUnit.Case, async: true

  test "Ash 3.x remains the canonical domain dependency" do
    mix = File.read!("mix.exs")
    assert mix =~ ~s({:ash, "~> 3.0 and >= 3.28.0"})
  end
end
