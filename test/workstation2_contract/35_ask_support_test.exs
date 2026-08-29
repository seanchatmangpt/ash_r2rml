# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.AskSupportTest do
  use ExUnit.Case, async: true
  test "local SPARQL backend retains ASK support" do
    assert File.read!("AGENTS.md") =~ "`SELECT`/`ASK`/`CONSTRUCT`/"
  end
end
