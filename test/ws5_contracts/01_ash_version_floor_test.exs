defmodule AshR2RML.WS5.AshVersionFloorTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "Ash integration preserves the 3.28 semantic API floor" do
    assert @mix =~ ~s({:ash, "~> 3.0 and >= 3.28.0"})
  end
end
