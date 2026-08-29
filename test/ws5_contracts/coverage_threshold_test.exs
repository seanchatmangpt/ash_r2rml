defmodule AshR2RML.WS5.CoverageThresholdTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "coverage quality threshold remains 70" do
    assert @manifest =~ "threshold: 70"
  end
end
