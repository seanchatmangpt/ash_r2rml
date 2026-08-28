defmodule AshR2RML.WS5.AshJsonApiTest do
  use ExUnit.Case, async: true
  test "AshJsonApi remains an explicit projection integration" do
    assert File.read!("mix.exs") =~ ~s({:ash_json_api, "~> 1.7", only: [:test]})
  end
end
