# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.QueryManyTest do
  use ExUnit.Case, async: true
  test "multi-resource querying remains explicit" do
    assert File.read!("AGENTS.md") =~ "`query_many/3` for cross-resource joins"
  end
end
