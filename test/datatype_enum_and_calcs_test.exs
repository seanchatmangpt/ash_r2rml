# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DatatypeEnumAndCalcsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  @xsd "http://www.w3.org/2001/XMLSchema#"

  defmodule Color do
    use Ash.Type.Enum, values: [:red, :green]
  end

  defmodule Status do
    use Ash.Type.NewType, subtype_of: :atom, constraints: [one_of: [:open, :closed]]
  end

  defmodule StatusOuter do
    use Ash.Type.NewType, subtype_of: AshR2RML.DatatypeEnumAndCalcsTest.Status
  end

  defmodule Cnt do
    use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 0]
  end

  test "Ash.Type.Enum resolves to xsd:string" do
    assert {:ok, dt} = Registry.resolve(Color)
    assert dt.rdf_datatype == @xsd <> "string"
  end

  test "Ash.Type.Atom resolves to xsd:string" do
    assert {:ok, dt} = Registry.resolve(Ash.Type.Atom)
    assert dt.rdf_datatype == @xsd <> "string"
  end

  test "NewType over atom with one_of resolves to xsd:string, nested too" do
    assert {:ok, a} = Registry.resolve(Status)
    assert {:ok, b} = Registry.resolve(StatusOuter)
    assert a.rdf_datatype == @xsd <> "string"
    assert b.rdf_datatype == @xsd <> "string"
  end

  test "unwrap preserves constraints through nested NewTypes" do
    {base, constraints} = Registry.unwrap(StatusOuter)
    assert base == Ash.Type.Atom
    assert constraints[:one_of] == [:open, :closed]

    {base, constraints} = Registry.unwrap(Cnt, max: 9)
    assert base == Ash.Type.Integer
    assert constraints[:min] == 0
    assert constraints[:max] == 9
  end

  test "unwrap leaves base types unchanged" do
    assert {Ash.Type.String, []} = Registry.unwrap(:string)
  end

  test "Range stays UNSUPPORTED_ASH_TYPE" do
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(Ash.Type.Range)
  end
end
