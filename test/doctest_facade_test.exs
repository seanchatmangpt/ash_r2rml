# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DoctestFacadeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.CompilationReceipt
  alias AshR2RML.GrandExample.Organization
  alias AshR2RML.Mapping.{Bundle, Resource}
  alias AshR2RML.Refusal

  test "mapping/1 returns the normalized mapping of a real resource" do
    assert %Resource{} = mapping = AshR2RML.mapping(Organization)
    assert mapping.logical_table.table_name == "schema_organizations"
  end

  test "mapping_result/1 returns {:ok, mapping} for a mapped resource" do
    assert {:ok, %Resource{}} = AshR2RML.mapping_result(Organization)
  end

  test "compile/1 closes a bundle over the resource" do
    assert {:ok, %Bundle{resources: [%Resource{}]}} = AshR2RML.compile([Organization])
  end

  test "render/1 and render_r2rml/1 produce identical Turtle for the same input" do
    assert {:ok, turtle} = AshR2RML.render([Organization])
    assert is_binary(turtle)
    assert turtle =~ "schema_organizations"
    assert {:ok, ^turtle} = AshR2RML.render_r2rml([Organization])
  end

  test "validate/1 yields a PARTIAL_ALIVE receipt that is not cutover ready" do
    assert %CompilationReceipt{status: :PARTIAL_ALIVE, classes_admitted: 1} =
             receipt = AshR2RML.validate([Organization])

    refute AshR2RML.Validation.cutover_ready?(receipt)
  end

  test "validate/1 turns a compile refusal into a REFUSED receipt" do
    assert %CompilationReceipt{status: :REFUSED, refusals: [%Refusal{}]} =
             AshR2RML.validate([String])
  end
end
