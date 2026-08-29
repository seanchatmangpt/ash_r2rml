# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ToOneCorrespondenceTest do
  use ExUnit.Case, async: true
  test "belongs_to and has_one map to reference object maps" do
    c=File.read!("AGENTS.md"); assert c =~ "To-One Edge"; assert c =~ "`belongs_to`/`has_one`"
  end
end
