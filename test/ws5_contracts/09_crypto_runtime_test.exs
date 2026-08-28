defmodule AshR2RML.WS5.CryptoRuntimeTest do
  use ExUnit.Case, async: true

  test "crypto remains an explicit runtime application" do
    assert File.read!("mix.exs") =~ "extra_applications: [:logger, :crypto]"
  end
end
