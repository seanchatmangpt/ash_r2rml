# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.SelectSupportTest do
  use ExUnit.Case, async: true
  test "local SPARQL backend retains SELECT support" do
    assert File.read!("AGENTS.md") =~ "`SELECT`/`ASK`/`CONSTRUCT`/"
  end
end
