defmodule AshR2RML.WS5.ChangelogMainlineLinkTest do
  use ExUnit.Case, async: true

  test "package changelog link resolves through main" do
    links = Mix.Project.config()[:package][:links]
    changelog = Map.fetch!(links, "Changelog")
    assert String.ends_with?(changelog, "/blob/main/CHANGELOG.md")
    assert changelog == links |> Map.fetch!("GitHub") |> Kernel.<>("/blob/main/CHANGELOG.md")
  end
end
