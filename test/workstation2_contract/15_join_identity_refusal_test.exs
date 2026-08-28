# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.JoinIdentityRefusalTest do
  use ExUnit.Case, async: true
  test "R2RML join without identity has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_R2RML_JOIN_WITHOUT_IDENTITY"
  end
end
