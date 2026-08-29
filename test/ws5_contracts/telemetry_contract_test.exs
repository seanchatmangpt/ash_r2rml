defmodule AshR2RML.WS5.TelemetryContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "telemetry dependency remains on 1.x" do
    assert @manifest =~ ~s({:telemetry, "~> 1.0"})
  end
end
