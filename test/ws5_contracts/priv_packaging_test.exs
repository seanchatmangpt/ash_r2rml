defmodule AshR2RML.WS5.PrivPackagingTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "priv semantic assets remain package-owned" do
    assert @manifest =~ "ash_r2rml.livemd priv"
  end
end
