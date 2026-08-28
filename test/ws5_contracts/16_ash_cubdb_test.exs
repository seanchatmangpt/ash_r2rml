defmodule AshR2RML.WS5.AshCubdbTest do
  use ExUnit.Case, async: true
  test "AshCubdb remains an explicit persistence integration" do
    assert File.read!("mix.exs") =~ ~s({:ash_cubdb, "~> 0.6.2", only: [:test]})
  end
end
