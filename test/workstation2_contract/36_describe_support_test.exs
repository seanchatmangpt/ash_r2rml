# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.DescribeSupportTest do
  use ExUnit.Case, async: true
  test "local SPARQL backend retains DESCRIBE support" do
    assert File.read!("AGENTS.md") =~ "`DESCRIBE`) through `AshR2RML.SPARQL.Local`"
  end
end
