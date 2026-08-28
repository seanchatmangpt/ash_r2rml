# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ExactExecutionStandingTest do
  use ExUnit.Case, async: true
  test "ALIVE requires execution against the exact admitted subject" do
    assert File.read!("AGENTS.md") =~ "`ALIVE` requires observed execution against the exact admitted subject"
  end
end
