defmodule AshR2RML.WS5.CoverageThresholdContractTest do
  use ExUnit.Case, async: true
  @mix Path.expand("../../mix.exs", __DIR__) |> File.read!()
  test "semantic compiler keeps the 70 percent coverage court" do
    assert @mix =~ "threshold: 70"
  end
end
