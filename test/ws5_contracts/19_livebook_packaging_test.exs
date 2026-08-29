defmodule AshR2RML.WS5.LivebookPackagingTest do
  use ExUnit.Case, async: true
  test "Livebook remains part of the package contract" do
    assert File.read!("mix.exs") =~ "ash_r2rml.livemd"
  end
end
