# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ReferenceIdentityTest do
  use ExUnit.Case, async: true
  test "reference joins target stable unique identities" do
    c = File.read!("AGENTS.md")
    assert c =~ "reference joins target stable unique identities"
  end
end
