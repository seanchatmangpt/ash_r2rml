# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupTripleClampTest do
  @moduledoc """
  The max_triples row clamp may only count triples a row is guaranteed to emit. A graph map
  that resolves nil, or a malformed stored `:iri` value, drops triples, so output that really
  fits `max_triples` must not be refused with `REFUSED_TRIPLE_LIMIT_EXCEEDED`.
  Real ETS-backed resources, real `AshR2RML.OBDA.InMemory.materialize/3`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Followup.{Domain, GraphRow, LinkRow}
  alias AshR2RML.Mapping.{Datatype, GraphMap, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  @thing "https://schema.org/Thing"
  @name_pred "https://schema.org/name"
  @url_pred "https://schema.org/url"
  @string "http://www.w3.org/2001/XMLSchema#string"

  setup do
    for resource <- [GraphRow, LinkRow] do
      resource
      |> Ash.read!(domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, domain: Domain))
    end

    :ok
  end

  defp create!(resource, params) do
    resource
    |> Ash.Changeset.for_create(:create, params, domain: Domain)
    |> Ash.create!(domain: Domain)
  end

  defp graph_mapping do
    %Resource{
      ash_resource: GraphRow,
      logical_table: %LogicalTable{table_name: "graph_rows"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
      class_iris: [@thing],
      graph_maps: [%GraphMap{strategy: :column, value: "graph"}],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @name_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:id]]
    }
  end

  defp iri_mapping do
    %Resource{
      ash_resource: LinkRow,
      logical_table: %LogicalTable{table_name: "link_rows"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :homepage,
          predicate_iri: @url_pred,
          object_map: %ObjectMap{strategy: :column, value: "homepage", term_type: :iri}
        }
      ],
      identities: [[:id]]
    }
  end

  describe "graph map resolving nil for every row" do
    test "output of zero triples fits max_triples: 2" do
      for n <- 1..3, do: create!(GraphRow, %{name: "n#{n}", nick: "k#{n}"})

      assert {:ok, graph} = InMemory.materialize(GraphRow, graph_mapping(), domain: Domain, max_triples: 2)
      assert RDF.Data.statement_count(graph) == 0
    end

    test "positive control: resolvable graphs emitting more than max_triples are still refused" do
      for n <- 1..3, do: create!(GraphRow, %{name: "n#{n}", nick: "k#{n}", graph: "urn:uuid:g#{n}"})

      assert {:error, %{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}} =
               InMemory.materialize(GraphRow, graph_mapping(), domain: Domain, max_triples: 2)
    end

    test "positive control: resolvable graph output that fits is admitted" do
      create!(GraphRow, %{name: "n1", nick: "k1", graph: "urn:uuid:g1"})

      assert {:ok, graph} = InMemory.materialize(GraphRow, graph_mapping(), domain: Domain, max_triples: 2)
      assert RDF.Data.statement_count(graph) == 2
    end
  end

  describe ":iri column with malformed stored values" do
    test "output of zero triples fits max_triples: 1" do
      for value <- ["not an iri", "has space", "bad>iri"], do: create!(LinkRow, %{homepage: value})

      assert {:ok, graph} = InMemory.materialize(LinkRow, iri_mapping(), domain: Domain, max_triples: 1)
      assert RDF.Data.statement_count(graph) == 0
    end

    test "positive control: a well-formed stored IRI is emitted" do
      create!(LinkRow, %{homepage: "https://schema.org/a"})

      assert {:ok, graph} = InMemory.materialize(LinkRow, iri_mapping(), domain: Domain, max_triples: 1)
      assert RDF.Data.statement_count(graph) == 1
    end

    test "positive control: well-formed IRIs beyond max_triples are refused" do
      for n <- 1..3, do: create!(LinkRow, %{homepage: "https://schema.org/p#{n}"})

      assert {:error, %{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}} =
               InMemory.materialize(LinkRow, iri_mapping(), domain: Domain, max_triples: 1)
    end
  end
end
