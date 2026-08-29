defmodule AshR2RML.WS5.CryptoAppTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "crypto remains an explicit runtime application" do
    assert @manifest =~ "extra_applications: [:logger, :crypto]"
  end
end
