# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DatatypeNewTypeAndNewMappingsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  @xsd "http://www.w3.org/2001/XMLSchema#"

  defmodule NtString do
    use Ash.Type.NewType, subtype_of: :string
  end

  defmodule NtInteger do
    use Ash.Type.NewType, subtype_of: :integer
  end

  defmodule NtNested do
    use Ash.Type.NewType, subtype_of: AshR2RML.DatatypeNewTypeAndNewMappingsTest.NtInteger
  end

  defmodule NtExplicit do
    use Ash.Type.NewType, subtype_of: :string

    def xsd_datatype, do: "http://example.org/dt#custom"
  end

  defmodule NtMap do
    use Ash.Type.NewType, subtype_of: :map
  end

  defmodule NtRange do
    use Ash.Type.NewType, subtype_of: Ash.Type.Range
  end

  defp iri!(type) do
    assert {:ok, dt} = Registry.resolve(type)
    dt.rdf_datatype
  end

  test "NewType over :string resolves to xsd:string" do
    assert iri!(NtString) == @xsd <> "string"
  end

  test "NewType over :integer resolves to xsd:integer" do
    assert iri!(NtInteger) == @xsd <> "integer"
  end

  test "nested NewType unwraps to the base xsd:integer" do
    assert iri!(NtNested) == @xsd <> "integer"
  end

  test "explicit xsd_datatype/0 on a NewType wins over the base type" do
    assert iri!(NtExplicit) == "http://example.org/dt#custom"
  end

  test "NewType over :map is refused UNSUPPORTED_ASH_TYPE" do
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(NtMap)
    refute Registry.supported?(NtMap)
  end

  test "NewType over Ash.Type.Range is refused UNSUPPORTED_ASH_TYPE" do
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(NtRange)
  end

  test "short-name and module forms resolve identically" do
    assert iri!(:string) == iri!(Ash.Type.String)
    assert iri!(:integer) == iri!(Ash.Type.Integer)
  end

  test "new mappings resolve to exact IRIs" do
    assert iri!(Ash.Type.UUIDv7) == @xsd <> "string"
    assert iri!(:uuid_v7) == @xsd <> "string"
    assert iri!(Ash.Type.Module) == @xsd <> "string"
    assert iri!(:module) == @xsd <> "string"
  end

  test "unsupported base types stay refused" do
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:map)
  end
end
