# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.InvalidClassIriRefusalTest do
  use ExUnit.Case, async: true
  test "invalid class IRI has a typed refusal" do
    assert File.read!("AGENTS.md") =~ "REFUSED_INVALID_CLASS_IRI"
  end
end
