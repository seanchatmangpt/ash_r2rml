defmodule AshR2RML.WS5.AshCsvTest do
  use ExUnit.Case, async: true

  test "AshCsv remains an explicit projection integration" do
    {:ash_csv, req, opts} = List.keyfind(Mix.Project.config()[:deps], :ash_csv, 0)
    assert req == "~> 0.9.8"
    assert opts[:only] == [:test]
    assert Code.ensure_loaded?(AshCsv.DataLayer)
  end
end
