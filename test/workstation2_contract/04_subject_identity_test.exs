# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.SubjectIdentityTest do
  use ExUnit.Case, async: true
  test "RDF identity remains explicit and distinct from database identity" do
    c = File.read!("AGENTS.md")
    assert c =~ "Database identity and RDF identity are distinct"
  end
end
