defmodule AshR2RML.WS5.ElixirFloorTest do
  use ExUnit.Case, async: true

  test "Elixir compatibility floor remains 1.17" do
    requirement = Mix.Project.config()[:elixir]
    assert requirement == "~> 1.17"
    assert Version.match?("1.17.0", requirement)
    refute Version.match?("1.16.9", requirement)
    assert Version.match?(System.version(), requirement)
  end
end
