defmodule AshR2RML.WS5.ReactorOptionalTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  test "Reactor remains an optional orchestration seam" do
    assert @manifest =~ ~s({:reactor, ">= 0.9.0", optional: true})
  end
end
