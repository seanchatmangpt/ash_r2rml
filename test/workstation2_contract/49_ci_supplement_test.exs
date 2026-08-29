# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.CiSupplementTest do
  use ExUnit.Case, async: true
  test "hosted CI supplements rather than replaces local proof" do
    assert File.read!("AGENTS.md") =~ "CI supplements local execution; it is not truth"
  end
end
