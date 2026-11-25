defmodule AshR2RML.WS5.TelemetryDependencyTest do
  use ExUnit.Case, async: true

  test "telemetry remains a production dependency" do
    {:telemetry, "~> 1.0"} = List.keyfind(Mix.Project.config()[:deps], :telemetry, 0)

    id = {__MODULE__, make_ref()}
    event = [:ash_r2rml, :ws5, :telemetry_probe]
    test_pid = self()

    handler = fn name, measurements, meta, _config ->
      send(test_pid, {:telemetry_seen, name, measurements, meta})
    end

    :ok = :telemetry.attach(id, event, handler, nil)

    try do
      :telemetry.execute(event, %{count: 1}, %{probe: true})
      assert_receive {:telemetry_seen, ^event, %{count: 1}, %{probe: true}}
    after
      :telemetry.detach(id)
    end
  end
end
