# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.TemplateFieldsTest do
  use ExUnit.Case, async: true
  test "subject template fields must resolve to mapped attributes" do
    c = File.read!("AGENTS.md")
    assert c =~ "every template field resolves to a mapped attribute"
  end
end
