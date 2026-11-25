# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SparkEcosystemTest do
  use ExUnit.Case, async: true

  @doc_path "documentation/reference/dsl_cheatsheet.md"

  defp sections, do: Map.new(AshR2RML.Resource.sections(), &{&1.name, &1})

  test "the extension compiles the r2rml and sparql sections with their entities" do
    sections = sections()
    assert Enum.sort(Map.keys(sections)) == [:r2rml, :sparql]

    r2rml_entities = Enum.map(sections.r2rml.entities, & &1.name)

    for name <- [:class, :subject, :property, :temporal, :reference, :graph] do
      assert name in r2rml_entities
    end

    assert Enum.map(sections.sparql.entities, & &1.name) == [:query]
  end

  test "the cheat sheet documents every compiled section and entity" do
    content = AshR2RML.CheatSheet.generate()
    assert byte_size(content) > 0

    for section <- AshR2RML.Resource.sections() do
      assert content =~ "#{section.name}"

      for entity <- section.entities do
        assert content =~ "#{entity.name}"
      end
    end
  end

  test "Mix.Tasks.AshR2rml.GenerateDocs writes exactly the generated cheat sheet" do
    assert :ok = Mix.Tasks.AshR2rml.GenerateDocs.run([])
    assert File.read!(@doc_path) == AshR2RML.CheatSheet.generate()
  end
end
