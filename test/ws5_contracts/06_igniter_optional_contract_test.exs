defmodule AshR2RML.WS5.IgniterOptionalContractTest do
  use ExUnit.Case, async: true

  test "Igniter is declared optional" do
    deps = Mix.Project.config()[:deps]
    {:igniter, requirement, opts} = List.keyfind(deps, :igniter, 0)

    assert is_binary(requirement)
    assert Keyword.get(opts, :optional) == true
  end
end
