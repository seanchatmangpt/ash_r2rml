# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.NormalizedIRTest do
  use ExUnit.Case, async: true
  test "all semantic workflows normalize before verification and rendering" do
    c = File.read!("AGENTS.md")
    assert c =~ "normalize into one deterministic mapping IR before verification/rendering"
  end
end
