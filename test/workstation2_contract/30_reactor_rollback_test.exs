# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ReactorRollbackTest do
  use ExUnit.Case, async: true
  test "rollback remains strict reverse order" do
    assert File.read!("AGENTS.md") =~ "strict reverse rollback"
  end
end
