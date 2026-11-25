# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW8TypesLensTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Money
  alias AshR2RML.Refusal

  @decimal "http://www.w3.org/2001/XMLSchema#decimal"

  test "non-string explicit datatype override is refused, not silently ignored" do
    assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} = Registry.resolve(Ash.Type.String, :not_an_iri)
  end

  test "string absolute override and nil override still resolve" do
    assert {:ok, %{rdf_datatype: @decimal}} = Registry.resolve(Ash.Type.String, @decimal)
    assert {:ok, _} = Registry.resolve(Ash.Type.String, nil)
  end

  test "money node with a non-binary decimal lexical is a typed refusal, not a crash" do
    node = {:node, %{amount: {:literal, 45, @decimal}, currency: "USD"}}
    assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} = Money.project(node)
  end
end
