# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ForbiddenFieldOmissionTest do
  use ExUnit.Case, async: true
  test "forbidden fields are omitted rather than projected" do
    assert File.read!("AGENTS.md") =~ "%Ash.ForbiddenField{}"
  end
end
