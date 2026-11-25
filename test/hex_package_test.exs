# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.HexPackageTest do
  use ExUnit.Case, async: true

  @files AshR2RML.MixProject.package_files()

  test "package keeps lib/mix out (repo owner decision)" do
    refute Enum.any?(@files, &String.starts_with?(&1, "lib/mix/"))
    assert "lib/ash_r2rml.ex" in @files
  end

  test "package contains only regular files and no excluded surfaces" do
    assert Enum.all?(@files, &File.regular?/1)
    refute Enum.any?(@files, &String.match?(&1, ~r/j[d]bc|on[t]op|\.jar$|^bench\//i))
  end
end
