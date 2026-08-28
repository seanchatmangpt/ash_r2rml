defmodule AshR2RML.WS5.SparkFloorTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Spark compatibility floor remains >= 2.7.0" do
    assert @manifest =~ ~s({:spark, ">= 2.7.0"})
  end
end
