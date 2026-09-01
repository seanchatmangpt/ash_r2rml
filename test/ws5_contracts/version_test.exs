defmodule AshR2RML.WS5.VersionContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "package version remains 26.8.26" do
    assert @manifest =~ ~s(@version "26.8.26")
  end
end
