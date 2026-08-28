defmodule AshR2RML.WS5.AshCsvTest do
  use ExUnit.Case, async: true
  test "AshCsv remains an explicit projection integration" do
    assert File.read!("mix.exs") =~ ~s({:ash_csv, "~> 0.9.8", only: [:test]})
  end
end
