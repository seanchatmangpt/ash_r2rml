defmodule AshR2RML.WS5.JasonDependencyTest do
  use ExUnit.Case, async: true
  test "Jason remains a production serialization dependency" do
    assert File.read!("mix.exs") =~ ~s({:jason, "~> 1.4"})
  end
end
