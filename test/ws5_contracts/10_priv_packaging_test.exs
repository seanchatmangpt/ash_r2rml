defmodule AshR2RML.WS5.PrivPackagingTest do
  use ExUnit.Case, async: true

  test "priv semantic artifacts remain part of the Hex package" do
    assert File.read!("mix.exs") =~ "LICENSE* CHANGELOG* ash_r2rml.livemd priv)"
  end
end
