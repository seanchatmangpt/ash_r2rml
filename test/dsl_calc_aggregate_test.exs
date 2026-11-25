# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DslCalcAggregateTest.Line do
  @moduledoc false
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :item_id, :uuid, public?: true
  end
end

defmodule AshR2RML.DslCalcAggregateTest.Item do
  @moduledoc false
  use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets, extensions: [AshR2RML.Resource]

  r2rml do
    table_name("calc_items")
    class("http://example.com/Item")

    subject do
      template("http://example.com/item/{id}")
    end

    property(:name, "http://example.com/name")
    property(:shout, "http://example.com/shout")
    property(:line_count, "http://example.com/lineCount")
  end

  actions do
    defaults [:read]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
  end

  relationships do
    has_many :lines, AshR2RML.DslCalcAggregateTest.Line,
      destination_attribute: :item_id,
      public?: true
  end

  calculations do
    calculate :shout, :string, expr(name <> "!"), public?: true
  end

  aggregates do
    count :line_count, :lines, public?: true
  end
end

defmodule AshR2RML.DslCalcAggregateTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DslCalcAggregateTest.Item
  alias AshR2RML.Resource.Info

  test "calculations and aggregates compile to predicate-object maps" do
    mapping = Info.mapping(Item)
    predicates = Map.new(mapping.predicate_object_maps, &{&1.attribute, &1.predicate_iri})

    assert predicates[:shout] == "http://example.com/shout"
    assert predicates[:line_count] == "http://example.com/lineCount"
    assert predicates[:name] == "http://example.com/name"
  end

  test "derived properties are recorded as read-only in mapping metadata" do
    mapping = Info.mapping(Item)

    assert mapping.metadata.derived_attributes == %{shout: :calculations, line_count: :aggregates}
  end
end
