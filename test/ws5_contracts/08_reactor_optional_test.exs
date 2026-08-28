defmodule AshR2RML.WS5.ReactorOptionalTest do
  use ExUnit.Case, async: true

  test "Reactor remains an optional workflow extension" do
    assert File.read!("mix.exs") =~ ~s({:reactor, ">= 0.9.0", optional: true})
  end
end
