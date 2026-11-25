defmodule AshR2RML.WS5.AshDependencyTest do
  use ExUnit.Case, async: true

  test "Ash 3.x is resolved, loaded, and a started-before application of ash_r2rml" do
    {:ok, applications} = :application.get_key(:ash_r2rml, :applications)
    assert :ash in applications
    assert {:module, Ash} = Code.ensure_loaded(Ash)
    assert {:module, Ash.Resource.Info} = Code.ensure_loaded(Ash.Resource.Info)

    {:ok, vsn} = :application.get_key(:ash, :vsn)
    assert {:ok, %Version{major: 3}} = Version.parse(to_string(vsn))
  end
end
