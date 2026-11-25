defmodule AshR2RML.WS5.CoverageThresholdContractTest do
  use ExUnit.Case, async: true

  test "semantic compiler keeps the 70 percent coverage court" do
    coverage = Mix.Project.config()[:test_coverage]
    assert coverage[:tool] == ExCoveralls
    assert get_in(coverage, [:summary, :threshold]) == 70
  end
end
