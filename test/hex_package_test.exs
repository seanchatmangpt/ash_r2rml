# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.HexPackageTest do
  use ExUnit.Case, async: true

  @files AshR2RML.MixProject.package_files()

  test "package ships the install and render mix tasks but not the dev-only generate_docs task" do
    assert "lib/mix/tasks/ash_r2rml.install.ex" in @files
    assert "lib/mix/tasks/ash_r2rml.render.ex" in @files
    refute "lib/mix/tasks/ash_r2rml.generate_docs.ex" in @files
    assert "lib/ash_r2rml.ex" in @files
  end

  test "the installer pins the CalVer series of this package" do
    source = File.read!("lib/mix/tasks/ash_r2rml.install.ex")
    assert source =~ ~s({:ash_r2rml, "~> 26.11"})
  end

  test "package contains only regular files and no excluded surfaces" do
    assert Enum.all?(@files, &File.regular?/1)
    refute Enum.any?(@files, &String.match?(&1, ~r/j[d]bc|on[t]op|\.jar$|^bench\//i))
  end
end
