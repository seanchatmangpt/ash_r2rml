defmodule AshR2RML.WS5.AshPostgresTest do
  use ExUnit.Case, async: true

  test "AshPostgres remains an explicit test integration" do
    {:ash_postgres, req, opts} = List.keyfind(Mix.Project.config()[:deps], :ash_postgres, 0)
    assert req == "~> 2.0"
    assert opts[:only] == [:test]
    assert Code.ensure_loaded?(AshPostgres.DataLayer)
  end
end
