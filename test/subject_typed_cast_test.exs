# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SubjectTypedCastTest do
  @moduledoc """
  Exact-state tests for typed subject keys: Ash.Type casting on `from_iri/2`, lexical
  encoding on `to_iri/2`, and the fail-closed refusals for absent keys and bad IRIs.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.{Refusal, Subject}

  defmodule Positive do
    use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 1]
  end

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.SubjectTypedCastTest.Typed
    end
  end

  defmodule Typed do
    use Ash.Resource, domain: AshR2RML.SubjectTypedCastTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]
    end

    attributes do
      uuid_primary_key :id
      attribute :num, :integer, public?: true
      attribute :day, :date, public?: true
      attribute :price, :decimal, public?: true
      attribute :pos, Positive, public?: true
      attribute :bounded, :integer, public?: true, constraints: [max: 10]
      attribute :name, :string, public?: true
    end
  end

  @ex "urn:uuid:"
  @uuid "0b1f6c3e-8d52-4a37-9c11-6a2e5d0f7b44"

  defp mapping(template) do
    %Resource{
      ash_resource: Typed,
      logical_table: %LogicalTable{table_name: "typed"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> template}
    }
  end

  defp refused(result, code), do: assert({:error, %Refusal{code: ^code}} = result)

  test "uuid segment casts and round trips" do
    m = mapping("t/{id}")
    assert Subject.from_iri(m, @ex <> "t/" <> @uuid) == {:ok, %{id: @uuid}}
    assert Subject.to_iri(m, %{id: @uuid}) == {:ok, @ex <> "t/" <> @uuid}
    refused(Subject.from_iri(m, @ex <> "t/not-a-uuid"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "integer segment casts to an integer" do
    m = mapping("n/{num}")
    assert Subject.from_iri(m, @ex <> "n/42") == {:ok, %{num: 42}}
    assert Subject.to_iri(m, %{num: 42}) == {:ok, @ex <> "n/42"}
    assert Subject.to_iri(m, %{num: "42"}) == {:ok, @ex <> "n/42"}
    refused(Subject.from_iri(m, @ex <> "n/abc"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "date segment casts to a Date" do
    m = mapping("d/{day}")
    assert Subject.from_iri(m, @ex <> "d/2026-11-24") == {:ok, %{day: ~D[2026-11-24]}}
    assert Subject.to_iri(m, %{day: ~D[2026-11-24]}) == {:ok, @ex <> "d/2026-11-24"}
    refused(Subject.from_iri(m, @ex <> "d/2026-13-45"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "decimal segment casts to a Decimal" do
    m = mapping("p/{price}")
    assert {:ok, %{price: price}} = Subject.from_iri(m, @ex <> "p/12.50")
    assert Decimal.equal?(price, Decimal.new("12.50"))
    assert Subject.to_iri(m, %{price: Decimal.new("12.50")}) == {:ok, @ex <> "p/12.50"}
    refused(Subject.from_iri(m, @ex <> "p/xx"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "NewType constraints apply on inversion" do
    m = mapping("w/{pos}")
    assert Subject.from_iri(m, @ex <> "w/3") == {:ok, %{pos: 3}}
    refused(Subject.from_iri(m, @ex <> "w/0"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "attribute constraints apply on inversion" do
    m = mapping("b/{bounded}")
    assert Subject.from_iri(m, @ex <> "b/10") == {:ok, %{bounded: 10}}
    refused(Subject.from_iri(m, @ex <> "b/11"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "values invalid for their type refuse on to_iri" do
    refused(Subject.to_iri(mapping("n/{num}"), %{num: "abc"}), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "strings are strictly percent-encoded to unreserved characters" do
    m = mapping("s/{name}")
    assert Subject.to_iri(m, %{name: "a b/c~d"}) == {:ok, @ex <> "s/a%20b%2Fc~d"}
    assert Subject.from_iri(m, @ex <> "s/a%20b%2Fc~d") == {:ok, %{name: "a b/c~d"}}
  end

  test "nil, forbidden and not-loaded keys refuse REFUSED_MISSING_SUBJECT_KEY" do
    m = mapping("n/{num}")
    refused(Subject.to_iri(m, %{num: nil}), :REFUSED_MISSING_SUBJECT_KEY)
    refused(Subject.to_iri(m, %{}), :REFUSED_MISSING_SUBJECT_KEY)
    refused(Subject.to_iri(m, %{num: %Ash.ForbiddenField{field: :num, type: :attribute}}), :REFUSED_MISSING_SUBJECT_KEY)
    refused(Subject.to_iri(m, %{num: %Ash.NotLoaded{field: :num, type: :attribute}}), :REFUSED_MISSING_SUBJECT_KEY)
  end

  test "adjacent placeholders refuse REFUSED_NON_INVERTIBLE_TEMPLATE on from_iri" do
    m = mapping("k/{num}{name}")
    refused(Subject.from_iri(m, @ex <> "k/1a"), :REFUSED_NON_INVERTIBLE_TEMPLATE)
  end

  test "non-canonical uuid casing fails the round trip rather than aliasing an identity" do
    m = mapping("t/{id}")
    assert {:error, %Refusal{}} = Subject.from_iri(m, @ex <> "t/" <> String.upcase(@uuid))
  end
end
