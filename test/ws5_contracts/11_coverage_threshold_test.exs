defmodule AshR2RML.WS5.CoverageThresholdTest do
  use ExUnit.Case, async: true
  test "coverage floor remains 70 percent" do
    assert File.read!("mix.exs") =~ "threshold: 70"
  end
end
