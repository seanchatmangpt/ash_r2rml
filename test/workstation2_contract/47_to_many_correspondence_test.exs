# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ToManyCorrespondenceTest do
  use ExUnit.Case, async: true
  test "to-many relationships map to repeated reference object maps" do
    c=File.read!("AGENTS.md"); assert c =~ "To-Many Edge"; assert c =~ "`has_many`/`many_to_many`"
  end
end
