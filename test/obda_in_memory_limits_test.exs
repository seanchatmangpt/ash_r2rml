# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryLimitsTest do
  @moduledoc """
  Bounds inside `AshR2RML.OBDA.InMemory`: `max_rows`, `max_triples`, row/triple stats and
  the constant-subject point-lookup pushdown, all against a real `Ash.DataLayer.Ets` resource.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryLimitsTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryLimitsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    ets do
      private? true
    end

    r2rml do
      class_iri("https://example.org/Item")
      subject_template("https://example.org/Item/{id}")
      table_name("limits_items")

      attribute_mappings([
        {:name, "https://example.org/name"}
      ])
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:name]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, public?: true
    end
  end

  @select "SELECT ?s ?name WHERE { ?s <https://example.org/name> ?name . }"

  setup do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(Item)

    items =
      for n <- 1..5 do
        Item
        |> Ash.Changeset.for_create(:create, %{name: "item-#{n}"}, domain: Domain)
        |> Ash.create!(domain: Domain)
      end

    {:ok, mapping: mapping, items: items}
  end

  test "defaults admit a small result and report stats", %{mapping: mapping} do
    assert {{:ok, observation}, stats} =
             InMemory.query_with_stats([{Item, mapping}], @select, domain: Domain)

    assert length(observation.rows) == 5
    assert stats.rows_read == 5
    # one rdf:type + one name triple per row
    assert stats.triples_emitted == 10
  end

  test "max_rows refuses when the read exceeds the limit", %{mapping: mapping} do
    assert {{:error, refusal}, stats} =
             InMemory.query_with_stats([{Item, mapping}], @select, domain: Domain, max_rows: 4)

    assert refusal.code == :REFUSED_RESULT_LIMIT_EXCEEDED
    assert refusal.evidence == %{resource: Item, limit: 4}
    assert stats.triples_emitted == 0

    assert {:error, %{code: :REFUSED_RESULT_LIMIT_EXCEEDED}} =
             InMemory.materialize(Item, mapping, domain: Domain, max_rows: 1)
  end

  test "max_rows equal to the row count is admitted", %{mapping: mapping} do
    assert {:ok, _graph} = InMemory.materialize(Item, mapping, domain: Domain, max_rows: 5)
  end

  test "max_triples refuses from the clamped read before any row is materialized", %{mapping: mapping} do
    assert {{:error, refusal}, stats} =
             InMemory.query_with_stats([{Item, mapping}], @select, domain: Domain, max_triples: 5)

    assert refusal.code == :REFUSED_TRIPLE_LIMIT_EXCEEDED
    assert refusal.evidence == %{resource: Item, limit: 5}
    # 2 guaranteed triples per row -> a budget of 5 admits at most 2 rows; the read is clamped to 3,
    # which provably exceeds the budget, so nothing is materialized.
    assert stats.triples_emitted == 0
    assert stats.rows_read == 0
  end

  test "max_triples equal to the emitted count is admitted", %{mapping: mapping} do
    assert {{:ok, _}, %{triples_emitted: 10}} =
             InMemory.query_with_stats([{Item, mapping}], @select, domain: Domain, max_triples: 10)
  end

  test "constant subject IRI pushes down so a point lookup reads one row", %{mapping: mapping, items: [item | _]} do
    iri = "https://example.org/Item/#{item.id}"

    assert {{:ok, observation}, stats} =
             InMemory.query_with_stats([{Item, mapping}], @select, domain: Domain, subject_iri: iri)

    assert stats.rows_read == 1
    assert observation.rows == [%{"s" => iri, "name" => item.name}]
  end

  test "a non-invertible subject IRI leaves the read unnarrowed", %{mapping: mapping} do
    assert {{:ok, _}, %{rows_read: 5}} =
             InMemory.query_with_stats([{Item, mapping}], @select,
               domain: Domain,
               subject_iri: "https://other.example/x"
             )
  end

  test "max_rows applies to the pushed-down read as well", %{mapping: mapping, items: [item | _]} do
    iri = "https://example.org/Item/#{item.id}"

    assert {:ok, _graph} =
             InMemory.materialize(Item, mapping, domain: Domain, subject_iri: iri, max_rows: 1)
  end
end
