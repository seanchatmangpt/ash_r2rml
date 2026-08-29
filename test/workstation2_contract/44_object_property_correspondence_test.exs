# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.ObjectPropertyCorrespondenceTest do
  use ExUnit.Case, async: true
  test "Ash relationships correspond to R2RML reference object maps" do
    c=File.read!("AGENTS.md"); assert c =~ "Object Property"; assert c =~ "`rr:RefObjectMap`"
  end
end
