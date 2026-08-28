defmodule AshR2RML.WS5.SparkDependencyTest do
  use ExUnit.Case, async: true

  test "Spark remains a production DSL dependency" do
    assert File.read!("mix.exs") =~ ~s({:spark, ">= 2.7.0"})
  end
end
