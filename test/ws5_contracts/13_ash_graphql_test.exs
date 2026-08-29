defmodule AshR2RML.WS5.AshGraphqlTest do
  use ExUnit.Case, async: true
  test "AshGraphql remains an explicit projection integration" do
    assert File.read!("mix.exs") =~ ~s({:ash_graphql, "~> 1.10", only: [:test]})
  end
end
