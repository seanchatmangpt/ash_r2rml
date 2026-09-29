# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.VKG.V26928DocsTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  defp read(rel), do: File.read!(Path.join(@root, rel))

  defp atoms_in(paths) do
    paths
    |> Enum.flat_map(fn p -> Regex.scan(~r/:?(REFUSED_[A-Z0-9_]+)/, File.read!(p), capture: :all_but_first) end)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Read through Code.Typespec, so the closure does not depend on how the type is
  # laid out in mapping.ex.
  defp refusal_codes, do: AshR2RML.VKGCase.refusal_codes()

  test "vkg source actually contains REFUSED atoms (guard against a vacuous grep)" do
    files = Path.wildcard(Path.join(@root, "lib/ash_r2rml/vkg/**/*.ex"))
    assert files != []
    atoms = atoms_in(files)
    assert "REFUSED_VKG_REPLAY" in atoms
    assert length(refusal_codes()) > 20
  end

  test "every REFUSED_ atom in lib/ash_r2rml/vkg is in Refusal.code() and AGENTS.md" do
    atoms = atoms_in(Path.wildcard(Path.join(@root, "lib/ash_r2rml/vkg/**/*.ex")))
    codes = refusal_codes()
    agents = read("AGENTS.md")

    for atom <- atoms do
      assert atom in codes, "#{atom} is used in lib/ash_r2rml/vkg but missing from Refusal.code()"
      assert agents =~ "`#{atom}`", "#{atom} is not documented in AGENTS.md"
    end
  end

  test "REFUSED_OBDA_EXECUTION and REFUSED_RESOURCE_BOUND are typed and documented" do
    agents = read("AGENTS.md")

    for a <- ["REFUSED_OBDA_EXECUTION", "REFUSED_RESOURCE_BOUND"] do
      assert a in refusal_codes()
      assert agents =~ "`#{a}`"
    end
  end

  test "usage-rules/vkg.md exists, is linked, and states the authority ceiling" do
    assert read("usage-rules.md") =~ "usage-rules/vkg.md"
    vkg = read("usage-rules/vkg.md")
    assert vkg =~ "Observe-only"
    assert vkg =~ "No DO"
    assert vkg =~ "Not network federation"
    assert read("README.md") =~ "observe-only"
  end

  test "package ships usage rules and AGENTS.md; docs group VKG modules" do
    mix = read("mix.exs")
    assert mix =~ "usage-rules.md usage-rules"
    assert mix =~ ~S(AshR2RML\.VKG)
  end

  test "CHANGELOG has a 26.9.28 section and the PRD/ARD exist" do
    assert read("CHANGELOG.md") =~ "## [v26.9.28]"
    assert File.exists?(Path.join(@root, "docs/jira/v26.9.28/VKG-001-virtual-knowledge-graph-federation-PRD.md"))
    assert File.exists?(Path.join(@root, "docs/jira/v26.9.28/VKG-001-virtual-knowledge-graph-federation-ARD.md"))
  end
end
