# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DslDocumentationTest do
  use ExUnit.Case, async: true

  defp nonempty?(s), do: is_binary(s) and String.trim(s) != ""

  defp walk(sections), do: Enum.flat_map(sections, &walk_section/1)

  defp walk_section(section) do
    nested = walk(section.sections || [])
    entities = Enum.flat_map(section.entities || [], &walk_entity/1)
    [{:section, section.name, section} | entities ++ nested]
  end

  defp walk_entity(entity) do
    nested =
      (entity.entities || [])
      |> Enum.flat_map(fn {_k, es} -> Enum.flat_map(List.wrap(es), &walk_entity/1) end)

    [{:entity, entity.name, entity} | nested]
  end

  defp nodes, do: walk(AshR2RML.Resource.sections())

  test "every section and entity has a non-empty describe" do
    missing = for {_k, name, n} <- nodes(), not nonempty?(n.describe), do: name
    assert missing == []
  end

  test "every section and entity has at least one example" do
    missing =
      for {_k, name, n} <- nodes(),
          not (is_list(n.examples) and n.examples != [] and Enum.all?(n.examples, &nonempty?/1)),
          do: name

    assert missing == []
  end

  test "cheat sheet contains every section and entity name" do
    sheet = Spark.CheatSheet.cheat_sheet(AshR2RML.Resource)
    assert nonempty?(sheet)

    missing =
      for {_k, name, _n} <- nodes(), not String.contains?(sheet, to_string(name)), do: name

    assert missing == []
  end
end
