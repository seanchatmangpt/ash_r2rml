defmodule AshR2RML.WS5.AshJsonApiTest do
  use ExUnit.Case, async: true

  test "AshJsonApi remains an explicit projection integration" do
    {:ash_json_api, req, opts} = List.keyfind(Mix.Project.config()[:deps], :ash_json_api, 0)
    assert req == "~> 1.7"
    assert opts[:only] == [:test]
    assert Code.ensure_loaded?(AshJsonApi)
  end
end
