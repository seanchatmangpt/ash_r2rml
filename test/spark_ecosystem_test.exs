# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SparkEcosystemTest do
  use ExUnit.Case, async: true

  test "AshR2RML.CheatSheet.generate/0 produces Spark DSL Markdown documentation" do
    content = AshR2RML.CheatSheet.generate()
    assert is_binary(content)
    assert content =~ "AshR2RML.Resource"
    assert content =~ "r2rml"
  end

  test "Mix.Tasks.AshR2rml.GenerateDocs runs successfully" do
    assert :ok = Mix.Tasks.AshR2rml.GenerateDocs.run([])
    assert File.exists?("documentation/reference/dsl_cheatsheet.md")
    content = File.read!("documentation/reference/dsl_cheatsheet.md")
    assert content =~ "AshR2RML.Resource"
  end
end
