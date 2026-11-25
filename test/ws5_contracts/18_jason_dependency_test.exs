defmodule AshR2RML.WS5.JasonDependencyTest do
  use ExUnit.Case, async: true

  test "Jason remains a production serialization dependency" do
    {:jason, "~> 1.4"} = List.keyfind(Mix.Project.config()[:deps], :jason, 0)

    value = %{"s" => "http://schema.org/name", "n" => [1, 2.5, nil, true], "t" => "café"}
    assert value |> Jason.encode!() |> Jason.decode!() == value
  end
end
