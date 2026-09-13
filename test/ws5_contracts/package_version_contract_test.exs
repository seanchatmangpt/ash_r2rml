defmodule AshR2RML.WS5.PackageVersionContractTest do
  use ExUnit.Case, async: true

  test "package version is declared and non-empty in mix.exs" do
    source = File.read!("mix.exs")
    assert [_, version] = Regex.run(~r/@version\s+"([^"]+)"/, source)
    assert version =~ ~r/^\d+\.\d+\.\d+/
  end
end
