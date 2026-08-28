defmodule AshR2RML.WS5.TelemetryDependencyTest do
  use ExUnit.Case, async: true
  test "telemetry remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:telemetry, "~> 1.0"})
  end
end
