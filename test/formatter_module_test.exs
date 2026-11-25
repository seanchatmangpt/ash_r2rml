# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FormatterModuleTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Formatter

  test "extensions/0 exports the AshR2RML resource extension" do
    assert Formatter.extensions() == [AshR2RML.Resource]
  end

  test "features/1 declares .ex and .exs" do
    assert Formatter.features([]) == [extensions: [".ex", ".exs"]]
  end

  test "format/2 returns formatted source as a binary for plain code" do
    out = Formatter.format("x   =   1\n", [])
    assert is_binary(out)
    assert out =~ "x = 1"
  end

  test "format/2 is idempotent" do
    once = Formatter.format("defmodule A do\n  def a, do: 1\nend\n", [])
    assert Formatter.format(once, []) == once
  end

  test "format/2 tolerates caller-supplied spark extensions option" do
    src = "y   =   2\n"
    out = Formatter.format(src, spark: [extensions: []])
    assert out == "y = 2\n"
    assert out == Formatter.format(src, [])
  end
end
