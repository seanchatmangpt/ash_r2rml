# SPDX-License-Identifier: MIT

defmodule AshR2RML.WS2.FieldPolicyStructuralTest do
  use ExUnit.Case, async: true
  test "field policies are excluded structurally before Ontop" do
    assert File.read!("AGENTS.md") =~ "strips any R2RML-mapped attribute that carries an explicit `field_policy`"
  end
end
