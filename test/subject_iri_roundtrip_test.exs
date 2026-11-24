# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SubjectIriRoundtripTest do
  @moduledoc """
  Exact-state tests for `AshR2RML.Subject`: single-key and composite-key subject IRI
  round trips, percent-encoding, every refusal code, and byte equality with the subject
  IRIs `AshR2RML.OBDA.InMemory` emits for the same real ETS records.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.{Refusal, Subject}

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.SubjectIriRoundtripTest.Item
      resource AshR2RML.SubjectIriRoundtripTest.Member
    end
  end

  defmodule Item do
    use Ash.Resource, domain: AshR2RML.SubjectIriRoundtripTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:slug]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :slug, :string, public?: true
    end
  end

  defmodule Member do
    use Ash.Resource, domain: AshR2RML.SubjectIriRoundtripTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:org, :pid]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :org, :string, public?: true
      attribute :pid, :string, public?: true
    end
  end

  @ex "http://ex.org/"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  defp mapping(resource, template, strategy \\ :template) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: strategy, value: template},
      class_iris: [@ex <> "Thing"]
    }
  end

  defp item_mapping, do: mapping(Item, @ex <> "item/{slug}")
  defp member_mapping, do: mapping(Member, @ex <> "orgs/{org}/people/{pid}")

  defp create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, domain: Dom)
    |> Ash.create!(domain: Dom)
  end

  defp emitted_subjects(resource, mapping) do
    sparql = "SELECT ?s WHERE { ?s <#{@rdf_type}> <#{@ex}Thing> }"
    assert {:ok, obs} = InMemory.query(resource, mapping, sparql, domain: Dom)
    obs.rows |> Enum.map(& &1["s"]) |> Enum.sort()
  end

  defp refused(result, code) do
    assert {:error, %Refusal{code: ^code}} = result
  end

  # -- single key -------------------------------------------------------------

  test "single-key to_iri encodes space, slash, hash and unicode exactly" do
    for {slug, encoded} <- [
          {"plain", "plain"},
          {"a b", "a%20b"},
          {"a/b", "a%2Fb"},
          {"a#b", "a%23b"},
          {"café", "caf%C3%A9"}
        ] do
      assert Subject.to_iri(item_mapping(), %{slug: slug}) == {:ok, @ex <> "item/" <> encoded}
      assert Subject.from_iri(item_mapping(), @ex <> "item/" <> encoded) == {:ok, %{slug: slug}}
    end
  end

  test "to_iri accepts keyword lists, string-keyed maps and real Ash records" do
    expected = {:ok, @ex <> "item/a%20b"}
    assert Subject.to_iri(item_mapping(), slug: "a b") == expected
    assert Subject.to_iri(item_mapping(), %{"slug" => "a b"}) == expected
    assert Subject.to_iri(item_mapping(), create!(Item, %{slug: "a b"})) == expected
  end

  test "from_iri then to_iri is the identity on the IRI" do
    iri = @ex <> "item/caf%C3%A9%2Fx"
    assert {:ok, values} = Subject.from_iri(item_mapping(), iri)
    assert values == %{slug: "café/x"}
    assert Subject.to_iri(item_mapping(), values) == {:ok, iri}
  end

  # -- composite key ----------------------------------------------------------

  test "composite-key round trip with exact IRI strings" do
    iri = @ex <> "orgs/acme/people/p1"
    assert Subject.to_iri(member_mapping(), %{org: "acme", pid: "p1"}) == {:ok, iri}
    assert Subject.from_iri(member_mapping(), iri) == {:ok, %{org: "acme", pid: "p1"}}
  end

  test "composite-key values are percent-encoded and decoded independently" do
    iri = @ex <> "orgs/eu%20west/people/w%2F1"
    assert Subject.to_iri(member_mapping(), org: "eu west", pid: "w/1") == {:ok, iri}
    assert Subject.from_iri(member_mapping(), iri) == {:ok, %{org: "eu west", pid: "w/1"}}
  end

  # -- resource module resolution ---------------------------------------------

  test "a resource without an r2rml mapping refuses rather than crashing" do
    assert {:error, %Refusal{}} = Subject.to_iri(Item, %{slug: "x"})
  end

  # -- refusals ---------------------------------------------------------------

  test "non-template subject maps refuse :UNSUPPORTED_TERM_TYPE in both directions" do
    m = mapping(Item, @ex <> "constant", :constant)
    refused(Subject.to_iri(m, %{slug: "x"}), :UNSUPPORTED_TERM_TYPE)
    refused(Subject.from_iri(m, @ex <> "constant"), :UNSUPPORTED_TERM_TYPE)
  end

  test "missing or nil template field refuses :REFUSED_MISSING_SUBJECT_KEY" do
    refused(Subject.to_iri(member_mapping(), %{org: "acme"}), :REFUSED_MISSING_SUBJECT_KEY)
    refused(Subject.to_iri(member_mapping(), %{org: "acme", pid: nil}), :REFUSED_MISSING_SUBJECT_KEY)
    refused(Subject.to_iri(item_mapping(), []), :REFUSED_MISSING_SUBJECT_KEY)
  end

  test "adjacent placeholders are not invertible" do
    m = mapping(Member, @ex <> "k/{org}{pid}")
    refused(Subject.from_iri(m, @ex <> "k/ab"), :REFUSED_NON_INVERTIBLE_TEMPLATE)
    assert Subject.to_iri(m, %{org: "a", pid: "b"}) == {:ok, @ex <> "k/ab"}
  end

  test "literal mismatch refuses" do
    refused(Subject.from_iri(item_mapping(), "http://other.org/item/x"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(member_mapping(), @ex <> "orgs/acme/staff/p1"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(item_mapping(), @ex <> "item/x/trailing"), :REFUSED_INVALID_TERM_MAP)
  end

  test "empty capture refuses" do
    refused(Subject.from_iri(item_mapping(), @ex <> "item/"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(member_mapping(), @ex <> "orgs//people/p1"), :REFUSED_INVALID_TERM_MAP)
  end

  test "malformed percent-encoding refuses" do
    refused(Subject.from_iri(item_mapping(), @ex <> "item/%ZZ"), :REFUSED_INVALID_TERM_MAP)
  end

  test "non-canonical encoding fails the roundtrip check" do
    refused(Subject.from_iri(item_mapping(), @ex <> "item/a%2fb"), :REFUSED_INVALID_TERM_MAP)
    refused(Subject.from_iri(item_mapping(), @ex <> "item/a b"), :REFUSED_INVALID_TERM_MAP)
  end

  test "non-string IRI refuses" do
    refused(Subject.from_iri(item_mapping(), nil), :REFUSED_INVALID_TERM_MAP)
  end

  # -- agreement with OBDA.InMemory ------------------------------------------

  test "to_iri equals the subject IRIs OBDA.InMemory emits for single-key records" do
    slugs = ["plain", "a b", "a/b", "a#b", "café"]
    records = Enum.map(slugs, &create!(Item, %{slug: &1}))

    expected =
      records
      |> Enum.map(fn r ->
        assert {:ok, iri} = Subject.to_iri(item_mapping(), r)
        iri
      end)
      |> Enum.sort()

    assert emitted_subjects(Item, item_mapping()) == expected

    for iri <- expected, do: assert({:ok, _} = Subject.from_iri(item_mapping(), iri))
  end

  test "to_iri equals the subject IRIs OBDA.InMemory emits for composite-key records" do
    records =
      Enum.map(
        [{"acme", "p1"}, {"eu west", "w/1"}, {"café", "x#y"}],
        fn {org, pid} -> create!(Member, %{org: org, pid: pid}) end
      )

    expected =
      records
      |> Enum.map(fn r ->
        assert {:ok, iri} = Subject.to_iri(member_mapping(), r)
        iri
      end)
      |> Enum.sort()

    assert emitted_subjects(Member, member_mapping()) == expected

    assert Enum.map(expected, fn iri ->
             assert {:ok, v} = Subject.from_iri(member_mapping(), iri)
             {v.org, v.pid}
           end)
           |> Enum.sort() == [{"acme", "p1"}, {"café", "x#y"}, {"eu west", "w/1"}]
  end
end
