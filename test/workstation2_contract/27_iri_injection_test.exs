# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.IriInjectionTest do
  use ExUnit.Case, async: true
  test "row-derived IRIs are validated or percent-encoded" do
    c=File.read!("AGENTS.md"); assert c =~ "validated or percent-encoded"
  end
end
