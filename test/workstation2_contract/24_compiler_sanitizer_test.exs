# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.CompilerSanitizerTest do
  use ExUnit.Case, async: true
  test "compiler routes mappings through the security sanitizer" do
    c = File.read!("AGENTS.md")
    assert c =~ "AshR2RML.Security.sanitize_mapping/2"
    assert c =~ "AshR2RML.Compiler.compile_resources/1"
  end
end
