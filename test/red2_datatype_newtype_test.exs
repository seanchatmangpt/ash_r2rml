# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2DatatypeNewTypeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Wide do
    use Ash.Type
    use AshR2RML.Type, datatype_iri: "http://www.w3.org/2001/XMLSchema#string"

    @impl Ash.Type
    def constraints, do: [wide: [type: :boolean]]

    @impl Ash.Type
    def storage_type(constraints) do
      if constraints[:wide], do: :varchar, else: :text
    end

    @impl Ash.Type
    def cast_input(value, _), do: {:ok, value}
    @impl Ash.Type
    def cast_stored(value, _), do: {:ok, value}
    @impl Ash.Type
    def dump_to_native(value, _), do: {:ok, value}

    @impl AshR2RML.Type
    def to_rdf_lexical(value), do: to_string(value)
    @impl AshR2RML.Type
    def from_rdf_lexical(value), do: {:ok, value}
  end

  defmodule WideNt do
    use Ash.Type.NewType, subtype_of: Wide, constraints: [wide: true]
  end

  test "raw array type with rdf override is refused" do
    assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} =
             Registry.resolve({:array, :string}, @xsd_string)
  end

  test "literal storage type honours merged NewType subtype constraints" do
    assert {:ok, %{storage_type: :varchar}} = Registry.resolve(WideNt)
  end
end
