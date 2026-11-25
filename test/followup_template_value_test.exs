# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupTemplateValueTest do
  @moduledoc """
  A template/column value with no `String.Chars` implementation (a real `:map` attribute)
  must skip the row, not crash `AshR2RML.OBDA.InMemory`. Real ETS resource, no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    GraphMap,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.FollowupTemplateValueTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource,
      domain: AshR2RML.FollowupTemplateValueTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :meta]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:meta, :map, public?: true)
    end
  end

  @pred "https://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"

  defp mapping(subject_map, graph_maps) do
    %Resource{
      ash_resource: Item,
      logical_table: %LogicalTable{table_name: "items"},
      subject_map: subject_map,
      graph_maps: graph_maps,
      class_iris: [],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "title",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:id]],
      metadata: %{source: :followup_template_value_test}
    }
  end

  setup do
    Item
    |> Ash.read!(domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, domain: Domain))

    Item
    |> Ash.Changeset.for_create(:create, %{title: "t", meta: %{"k" => 1}}, domain: Domain)
    |> Ash.create!(domain: Domain)

    :ok
  end

  defp triple_count(graph), do: graph |> RDF.Graph.triples() |> length()

  test "subject template over a value without String.Chars skips the row" do
    subject = %SubjectMap{strategy: :template, value: "http://schema.org/item/{meta}", term_type: :iri}
    assert {:ok, graph} = InMemory.materialize(Item, mapping(subject, []), domain: Domain)
    assert triple_count(graph) == 0
  end

  test "subject column over a value without String.Chars skips the row" do
    subject = %SubjectMap{strategy: :column, value: "meta", term_type: :iri}
    assert {:ok, graph} = InMemory.materialize(Item, mapping(subject, []), domain: Domain)
    assert triple_count(graph) == 0
  end

  test "graph template over a value without String.Chars drops the graph name" do
    subject = %SubjectMap{strategy: :template, value: "http://schema.org/item/{title}", term_type: :iri}
    graph_map = %GraphMap{strategy: :template, value: "http://schema.org/graph/{meta}"}

    assert {:ok, dataset} =
             InMemory.materialize_dataset([{Item, mapping(subject, [graph_map])}], domain: Domain)

    assert RDF.Dataset.graph_names(dataset) |> Enum.reject(&is_nil/1) == []
  end

  test "a String.Chars value still materializes (control)" do
    subject = %SubjectMap{strategy: :template, value: "http://schema.org/item/{title}", term_type: :iri}
    assert {:ok, graph} = InMemory.materialize(Item, mapping(subject, []), domain: Domain)
    assert triple_count(graph) == 1
  end
end
