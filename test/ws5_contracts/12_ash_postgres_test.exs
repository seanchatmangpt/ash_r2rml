defmodule AshR2RML.WS5.AshPostgresTest do
  use ExUnit.Case, async: true
  test "AshPostgres remains an explicit test integration" do
    assert File.read!("mix.exs") =~ ~s({:ash_postgres, "~> 2.0", only: [:test]})
  end
end
