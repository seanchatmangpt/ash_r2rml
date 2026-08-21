# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.ResourceTest.Organization do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2ML.Resource]

  r2rml do
    table_name "organizations"

    class "https://www.w3.org/ns/org#Organization"

    subject do
      template "https://example.test/organization/{id}"
    end

    property :name, "http://xmlns.com/foaf/0.1/name"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2ML.ResourceTest.Account do
  use Ash.Resource,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2ML.Resource]

  r2rml do
    table_name "accounts"

    class "https://example.test/ontology/Account"

    subject do
      template "https://example.test/account/{id}"
    end

    property :account_number, "https://example.test/ontology/accountNumber"
    reference :organization, "https://www.w3.org/ns/org#memberOf"
  end

  attributes do
    uuid_primary_key :id
    attribute :account_number, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :organization, AshR2ML.ResourceTest.Organization,
      allow_nil?: false,
      public?: true
  end
end

defmodule AshR2ML.ResourceTest do
  use ExUnit.Case, async: true

  alias AshR2ML.ResourceTest.{Account, Organization}

  test "Ash-first resource mapping is persisted as the public canonical IR" do
    mapping = AshR2ML.Resource.Info.mapping!(Account)

    assert %AshR2ML.Mapping.Resource{} = mapping
    assert mapping.ash_resource == Account
    assert mapping.class_iris == ["https://example.test/ontology/Account"]
    assert mapping.logical_table.table_name == "accounts"
    assert mapping.subject_map.value == "https://example.test/account/{id}"
    assert mapping.identities == [[:id]]

    assert [%AshR2ML.Mapping.PredicateObjectMap{} = property] = mapping.predicate_object_maps
    assert property.attribute == :account_number
    assert property.object_map.value == "account_number"

    assert [%AshR2ML.Mapping.ReferenceObjectMap{} = reference] = mapping.reference_object_maps
    assert reference.parent_resource == Organization
    assert reference.metadata.kind == :belongs_to
    assert [%AshR2ML.Mapping.JoinCondition{child: "organization_id", parent: "id"}] = reference.joins
  end

  test "Ash-first relationship targets expand to dependency closure before rendering" do
    assert {:ok, %AshR2ML.Mapping.Bundle{} = bundle} = AshR2ML.compile(Account)
    assert length(bundle.resources) == 2

    assert Enum.any?(bundle.resources, &(&1.ash_resource == Account))
    assert Enum.any?(bundle.resources, &(&1.ash_resource == Organization))
    assert :ok = AshR2ML.Mapping.validate(bundle)

    assert {:ok, ttl} = AshR2ML.render(bundle)
    assert ttl =~ "rr:TriplesMap"
    assert ttl =~ ~s(rr:tableName "accounts")
    assert ttl =~ ~s(rr:tableName "organizations")
    assert ttl =~ ~s(rr:child "organization_id"; rr:parent "id")
  end

  test "semantic subject identity is derived from Ash identity even when id is not an RDF property" do
    mapping = AshR2ML.Resource.Info.mapping!(Organization)

    assert mapping.identities == [[:id]]
    assert AshR2ML.Mapping.stable_subject_identity?(mapping)

    id_emitted? =
      Enum.any?(mapping.predicate_object_maps, fn property ->
        property.attribute == :id
      end)

    refute id_emitted?
    assert :ok = AshR2ML.Mapping.validate(mapping)
  end
end
