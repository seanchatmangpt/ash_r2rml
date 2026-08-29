# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.UnmappedDatatypeRefusalTest do
  use ExUnit.Case, async: true
  test "unmapped datatype has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_UNMAPPED_DATATYPE"
  end
end
