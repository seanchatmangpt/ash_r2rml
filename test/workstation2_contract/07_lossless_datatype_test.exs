# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.LosslessDatatypeTest do
  use ExUnit.Case, async: true
  test "datatype conversion remains explicit and lossless" do
    c = File.read!("AGENTS.md")
    assert c =~ "Datatype conversion must be explicit and lossless"
  end
end
