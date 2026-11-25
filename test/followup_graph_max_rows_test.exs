# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FollowupGraphMaxRowsTest do
  @moduledoc """
  `GRAPH ?g { ... }` merges per-graph observations; the merged result must still honor
  `max_rows` (`REFUSED_RESULT_LIMIT_EXCEEDED`) even when each graph and the Ash read are
  individually within the bound. Real ETS-backed resource, real `InMemory.query/4`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Followup.{Domain, GraphRow}
  alias AshR2RML.Mapping.{Datatype, GraphMap, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  @name_pred "https://schema.org/name"
  @nick_pred "https://schema.org/alternateName"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?g ?s ?p ?o WHERE { GRAPH ?g { ?s ?p ?o } }"

  setup do
    GraphRow
    |> Ash.read!(domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, domain: Domain))

    # 2 rows, each in its own named graph, each emitting 2 triples: 4 solutions in total.
    for n <- 1..2 do
      GraphRow
      |> Ash.Changeset.for_create(:create, %{name: "n#{n}", nick: "k#{n}", graph: "urn:uuid:g#{n}"}, domain: Domain)
      |> Ash.create!(domain: Domain)
    end

    :ok
  end

  defp pom(attribute, predicate) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: predicate,
      object_map: %ObjectMap{
        strategy: :column,
        value: Atom.to_string(attribute),
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
      }
    }
  end

  defp mapping do
    %Resource{
      ash_resource: GraphRow,
      logical_table: %LogicalTable{table_name: "graph_rows"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{id}", term_type: :iri},
      graph_maps: [%GraphMap{strategy: :column, value: "graph"}],
      predicate_object_maps: [pom(:name, @name_pred), pom(:nick, @nick_pred)],
      identities: [[:id]]
    }
  end

  test "merged GRAPH ?g solutions above max_rows are refused" do
    assert {:error, %{code: :REFUSED_RESULT_LIMIT_EXCEEDED}} =
             InMemory.query(GraphRow, mapping(), @select, domain: Domain, max_rows: 2)
  end

  test "positive control: the same query with max_rows covering all solutions returns them" do
    assert {:ok, observation} = InMemory.query(GraphRow, mapping(), @select, domain: Domain, max_rows: 4)
    assert length(observation.rows) == 4
  end
end
