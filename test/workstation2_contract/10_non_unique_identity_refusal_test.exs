# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.NonUniqueIdentityRefusalTest do
  use ExUnit.Case, async: true
  test "non-unique semantic identity has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY"
  end
end
