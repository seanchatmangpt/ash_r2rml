defmodule AshR2RML.WS5.JSONLDDependencyTest do
  use ExUnit.Case, async: true

  test "JSON-LD interoperability remains a production dependency" do
    assert File.read!("mix.exs") =~ ~s({:json_ld, "~> 1.0.1"})
  end
end
