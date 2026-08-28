defmodule AshR2RML.WS5.SparkFormatterAliasTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Spark formatter remains bound to AshR2RML.Resource" do
    assert @manifest =~ ~s("spark.formatter": "spark.formatter --extensions AshR2RML.Resource")
  end
end
