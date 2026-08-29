defmodule AshR2RML.WS5.SparkVersionFloorTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "Spark extension integration preserves the 2.7 floor" do
    assert @mix =~ ~s({:spark, ">= 2.7.0"})
  end
end
