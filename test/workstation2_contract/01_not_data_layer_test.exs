# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.NotDataLayerTest do
  use ExUnit.Case, async: true
  test "AshR2RML remains a semantic compiler, not an Ash.DataLayer" do
    contract = File.read!("AGENTS.md")
    assert contract =~ "not an `Ash.DataLayer`"
  end
end
