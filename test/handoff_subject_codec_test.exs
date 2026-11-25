# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.HandoffSubjectCodecTest do
  @moduledoc """
  Round-trip and refusal laws for `Subject.to_iri/2` / `from_iri/2` over composite keys,
  typed keys, NewType keys and reserved/non-ASCII characters; foreign or garbled IRIs
  refuse typed.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.{Refusal, Subject}

  defmodule Code do
    use Ash.Type.NewType, subtype_of: :integer, constraints: [min: 1]
  end

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.HandoffSubjectCodecTest.Rec
    end
  end

  defmodule Rec do
    use Ash.Resource, domain: AshR2RML.HandoffSubjectCodecTest.Dom, data_layer: Ash.DataLayer.Ets

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
      attribute :code, Code, public?: true
      attribute :name, :string, public?: true
      attribute :tag, :string, public?: true
    end
  end

  @ex "http://xmlns.com/foaf/0.1/"
  @uuid "0b1f6c3e-8d52-4a37-9c11-6a2e5d0f7b44"

  defp mapping(template) do
    %Resource{
      ash_resource: Rec,
      logical_table: %LogicalTable{table_name: "rec"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> template}
    }
  end

  defp refused(result, code), do: assert({:error, %Refusal{code: ^code}} = result)

  defp roundtrip(m, keys) do
    assert {:ok, iri} = Subject.to_iri(m, keys)
    assert {:ok, back} = Subject.from_iri(m, iri)
    {iri, back}
  end

  test "composite uuid/integer/date/NewType key round trips" do
    m = mapping("r/{id}/{num}/{day}/{code}")
    keys = %{id: @uuid, num: -5, day: ~D[2026-02-28], code: 7}
    {iri, back} = roundtrip(m, keys)
    assert iri == @ex <> "r/" <> @uuid <> "/-5/2026-02-28/7"
    assert back == keys
  end

  test "keyword-list keys produce the same IRI as a map" do
    m = mapping("r/{num}/{name}")
    assert Subject.to_iri(m, num: 3, name: "x") == Subject.to_iri(m, %{num: 3, name: "x"})
  end

  test "reserved, space, percent and non-ASCII characters round trip" do
    m = mapping("s/{name}/{tag}")

    for name <- ["a/b", "a?b#c", "q&r=s", "100%", "a b", "é☃", "%41", "x:y@z", "a+b"] do
      keys = %{name: name, tag: "t"}
      {iri, back} = roundtrip(m, keys)
      assert back == keys
      refute iri |> String.replace_prefix(@ex <> "s/", "") |> String.contains?(["?", "#", " "])
    end
  end

  test "non-ASCII is encoded as upper-case UTF-8 percent bytes" do
    assert Subject.to_iri(mapping("s/{name}"), %{name: "é"}) == {:ok, @ex <> "s/%C3%A9"}
  end

  test "empty string key refuses on to_iri" do
    refused(Subject.to_iri(mapping("s/{name}"), %{name: ""}), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "missing composite member refuses typed" do
    m = mapping("r/{id}/{num}")
    refused(Subject.to_iri(m, %{id: @uuid}), :REFUSED_MISSING_SUBJECT_KEY)
  end

  test "foreign IRI refuses typed" do
    m = mapping("r/{num}")
    refused(Subject.from_iri(m, "urn:sha256:r/1"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, "urn:uuid:" <> @uuid), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, ""), :REFUSED_INVALID_TERM_MAP)
  end

  test "garbled IRIs refuse typed" do
    m = mapping("s/{name}/{tag}")
    refused(Subject.from_iri(m, @ex <> "s/a%ZZ/t"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, @ex <> "s/a%/t"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, @ex <> "s//t"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, @ex <> "s/a/"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, @ex <> "s/a"), :REFUSED_INVALID_TERM_MAP)
  end

  test "non-canonical encodings alias no identity" do
    m = mapping("s/{name}/{tag}")
    refused(Subject.from_iri(m, @ex <> "s/a%2fb/t"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, @ex <> "s/%41/t"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, @ex <> "s/a/t/u"), :REFUSED_INVALID_TERM_MAP)
  end

  test "typed members that do not cast refuse INVALID_SUBJECT_IRI" do
    m = mapping("r/{num}/{day}/{code}")
    refused(Subject.from_iri(m, @ex <> "r/x/2026-01-01/1"), :REFUSED_INVALID_SUBJECT_IRI)
    refused(Subject.from_iri(m, @ex <> "r/1/2026-99-01/1"), :REFUSED_INVALID_SUBJECT_IRI)
    refused(Subject.from_iri(m, @ex <> "r/1/2026-01-01/0"), :REFUSED_INVALID_SUBJECT_IRI)
    refused(Subject.from_iri(m, @ex <> "r/1/2026-01-01/1/extra"), :REFUSED_INVALID_SUBJECT_IRI)
  end

  test "non-string IRI refuses typed" do
    m = mapping("r/{num}")
    refused(Subject.from_iri(m, nil), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(m, 42), :REFUSED_INVALID_TERM_MAP)
  end

  test "unknown template field and non-template strategy refuse typed" do
    refused(Subject.from_iri(mapping("r/{zz_no_such_field_q}"), @ex <> "r/1"), :REFUSED_INVALID_TERM_MAP)

    constant = %Resource{
      ash_resource: Rec,
      logical_table: %LogicalTable{table_name: "rec"},
      subject_map: %SubjectMap{strategy: :constant, value: @ex <> "fixed"}
    }

    refused(Subject.to_iri(constant, %{}), :UNSUPPORTED_TERM_TYPE)
    refused(Subject.from_iri(constant, @ex <> "fixed"), :UNSUPPORTED_TERM_TYPE)
  end

  test "ambiguous and adjacent separators refuse NON_INVERTIBLE on from_iri" do
    refused(Subject.from_iri(mapping("r/{name}-{tag}"), @ex <> "r/a-b"), :REFUSED_NON_INVERTIBLE_TEMPLATE)
    refused(Subject.from_iri(mapping("r/{num}{name}"), @ex <> "r/1a"), :REFUSED_NON_INVERTIBLE_TEMPLATE)
  end
end
