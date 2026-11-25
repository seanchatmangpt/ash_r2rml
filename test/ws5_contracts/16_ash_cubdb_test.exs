defmodule AshR2RML.WS5.AshCubdbTest do
  use ExUnit.Case, async: true

  test "AshCubdb remains an explicit persistence integration" do
    {:ash_cubdb, req, opts} = List.keyfind(Mix.Project.config()[:deps], :ash_cubdb, 0)
    assert req == "~> 0.6.2"
    assert opts[:only] == [:test]
    assert Code.ensure_loaded?(AshCubDB.DataLayer)
  end
end
