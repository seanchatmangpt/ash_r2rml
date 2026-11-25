# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedTypeRegistryTest do
  @moduledoc """
  Red-before-green courts for H02 (`AshR2RML.Type.__using__/1` option handling)
  and H26 (`Datatype.Registry` fail-open on invalid literal contracts, `:array`).
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule InvalidIriNil do
    use Ash.Type
    use AshR2RML.Type, semantic_kind: :literal, datatype_iri: nil

    @impl Ash.Type
    def storage_type(_), do: :text
    @impl Ash.Type
    def cast_input(v, _), do: {:ok, v}
    @impl Ash.Type
    def cast_stored(v, _), do: {:ok, v}
    @impl Ash.Type
    def dump_to_native(v, _), do: {:ok, v}
    @impl AshR2RML.Type
    def to_rdf_lexical(v), do: to_string(v)
    @impl AshR2RML.Type
    def from_rdf_lexical(v), do: {:ok, v}
  end

  defmodule InvalidIriRelative do
    use Ash.Type
    use AshR2RML.Type, semantic_kind: :literal, datatype_iri: "not-an-absolute-iri"

    @impl Ash.Type
    def storage_type(_), do: :text
    @impl Ash.Type
    def cast_input(v, _), do: {:ok, v}
    @impl Ash.Type
    def cast_stored(v, _), do: {:ok, v}
    @impl Ash.Type
    def dump_to_native(v, _), do: {:ok, v}
    @impl AshR2RML.Type
    def to_rdf_lexical(v), do: to_string(v)
    @impl AshR2RML.Type
    def from_rdf_lexical(v), do: {:ok, v}
  end

  test "H02 attribute-valued semantic_kind :literal still defaults datatype to xsd:string" do
    defmodule AttrKindType do
      @kind :literal
      use AshR2RML.Type, semantic_kind: @kind

      def to_rdf_lexical(v), do: to_string(v)
    end

    assert AttrKindType.semantic_kind() == :literal
    assert AttrKindType.datatype_iri() == @xsd_string
    assert AttrKindType.to_rdf("x") == {:literal, "x", @xsd_string}
  end

  test "H02 attribute-valued shacl_constraints are evaluated, not stored as raw AST" do
    defmodule AttrShaclType do
      @min 3
      use AshR2RML.Type, shacl_constraints: [min_length: @min]

      def to_rdf_lexical(v), do: to_string(v)
    end

    assert AttrShaclType.shacl_constraints() == [min_length: 3]
  end

  test "H02 attribute-valued datatype_iri is honoured in the encoded literal" do
    defmodule AttrIriType do
      @iri "http://schema.org/Text"
      use AshR2RML.Type, datatype_iri: @iri

      def to_rdf_lexical(v), do: to_string(v)
    end

    assert AttrIriType.datatype_iri() == "http://schema.org/Text"
    assert AttrIriType.to_rdf("x") == {:literal, "x", "http://schema.org/Text"}
  end

  test "H26 literal type with nil datatype_iri is refused as REFUSED_UNMAPPED_DATATYPE" do
    assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} = Registry.resolve(InvalidIriNil)
  end

  test "H26 literal type with non-absolute datatype_iri is refused, not silently resolved" do
    assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} =
             Registry.resolve(InvalidIriRelative)
  end

  test "H26 resolve(:array) is refused consistently with resolve({:array, :string})" do
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve({:array, :string})
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:array)
  end

  test "H26 builtin_contracts no longer admits :array" do
    refute Map.has_key?(Registry.builtin_contracts(), :array)
  end
end
