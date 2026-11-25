# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7JoinSerializationTest do
  @moduledoc """
  Parent subject IRIs and child join-key IRIs share one lexical serializer, so a join on a
  `:utc_datetime` or `:decimal` key emits the reference triple instead of silently dropping it.
  Real `Ash.DataLayer.Ets` rows, real `RDF.Graph`.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Mapping.{
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.OBDA.InMemory.IriTemplate

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW7JoinSerializationTest.Slot
      resource AshR2RML.RefactorW7JoinSerializationTest.Booking
      resource AshR2RML.RefactorW7JoinSerializationTest.Tier
      resource AshR2RML.RefactorW7JoinSerializationTest.Offer
    end
  end

  defmodule Slot do
    use Ash.Resource, domain: AshR2RML.RefactorW7JoinSerializationTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:at]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :at, :utc_datetime, public?: true
    end
  end

  defmodule Booking do
    use Ash.Resource, domain: AshR2RML.RefactorW7JoinSerializationTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:ref, :starts_at]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :ref, :string, public?: true
      attribute :starts_at, :utc_datetime, public?: true
    end
  end

  defmodule Tier do
    use Ash.Resource, domain: AshR2RML.RefactorW7JoinSerializationTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:amount]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :amount, :decimal, public?: true
    end
  end

  defmodule Offer do
    use Ash.Resource, domain: AshR2RML.RefactorW7JoinSerializationTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:ref, :price]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :ref, :string, public?: true
      attribute :price, :decimal, public?: true
    end
  end

  defp ref_mapping(resource, template, parent, predicate, child, parent_field) do
    ref = %ReferenceObjectMap{
      relationship: :parent,
      predicate_iri: predicate,
      parent_resource: parent,
      joins: [%JoinCondition{child: child, parent: parent_field}]
    }

    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: :template, value: template},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :ref,
          predicate_iri: "http://schema.org/name",
          object_map: %ObjectMap{strategy: :column, value: "ref"}
        }
      ],
      reference_object_maps: [ref]
    }
  end

  defp parent_mapping(resource, template) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Atom.to_string(resource)},
      subject_map: %SubjectMap{strategy: :template, value: template},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: []
    }
  end

  defp create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs, domain: Dom)
    |> Ash.create!(domain: Dom)
  end

  defp has_triple?({:ok, graph}, s, p, o) do
    graph |> RDF.Graph.triples() |> Enum.member?({RDF.iri(s), RDF.iri(p), RDF.iri(o)})
  end

  test "lexical form is ISO 8601 for datetimes and plain notation for decimals" do
    assert IriTemplate.substitute("http://schema.org/e-{at}", %{at: ~U[2026-01-02 03:04:05Z]}) ==
             "http://schema.org/e-2026-01-02T03%3A04%3A05Z"

    assert IriTemplate.substitute("http://schema.org/p-{n}", %{n: Decimal.new("1E+3")}) ==
             "http://schema.org/p-1000"

    assert IriTemplate.substitute("http://schema.org/s-{n}", %{n: 42}) == "http://schema.org/s-42"
  end

  test "join on a utc_datetime key emits the reference triple" do
    at = ~U[2026-01-02 03:04:05Z]
    create!(Slot, %{at: at})
    create!(Booking, %{ref: "b1", starts_at: at})

    specs = [
      {Booking,
       ref_mapping(
         Booking,
         "http://schema.org/booking-{ref}",
         Slot,
         "http://schema.org/memberOf",
         "starts_at",
         "at"
       )},
      {Slot, parent_mapping(Slot, "http://schema.org/slot-{at}")}
    ]

    assert has_triple?(
             InMemory.materialize_many(specs, domain: Dom),
             "http://schema.org/booking-b1",
             "http://schema.org/memberOf",
             "http://schema.org/slot-2026-01-02T03%3A04%3A05Z"
           )
  end

  test "join on a decimal key with exponent notation emits the reference triple" do
    create!(Tier, %{amount: Decimal.new("1E+3")})
    create!(Offer, %{ref: "o1", price: Decimal.new("1E+3")})

    specs = [
      {Offer,
       ref_mapping(
         Offer,
         "http://schema.org/offer-{ref}",
         Tier,
         "http://schema.org/memberOf",
         "price",
         "amount"
       )},
      {Tier, parent_mapping(Tier, "http://schema.org/tier-{amount}")}
    ]

    assert has_triple?(
             InMemory.materialize_many(specs, domain: Dom),
             "http://schema.org/offer-o1",
             "http://schema.org/memberOf",
             "http://schema.org/tier-1000"
           )
  end
end
