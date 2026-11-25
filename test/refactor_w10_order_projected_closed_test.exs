# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW10OrderProjectedClosedTest do
  @moduledoc """
  A SELECT with ORDER BY whose SELECT clause text cannot be matched is refused through
  `AshR2RML.OBDA.query/3` instead of failing open; other forms and no-ORDER-BY queries are untouched.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @ex "urn:uuid:"
  @s "http://schema.org/"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW10OrderProjectedClosedTest.Person
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.RefactorW10OrderProjectedClosedTest.Dom,
      data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:code, :name, :rank]
      end
    end

    attributes do
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
      attribute :rank, :string, public?: true
    end

    identities do
      identity :by_code, [:code], pre_check_with: AshR2RML.RefactorW10OrderProjectedClosedTest.Dom
    end
  end

  setup_all do
    for {code, name, rank} <- [{"p1", "carol", "c"}, {"p2", "alice", "b"}, {"p3", "bob", "a"}] do
      Ash.create!(Person, %{code: code, name: name, rank: rank}, domain: Dom)
    end

    :ok
  end

  @dt %Datatype{ash_type: :string, rdf_datatype: @xsd_string}

  defp pom(attribute, predicate) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: @s <> predicate,
      object_map: %ObjectMap{strategy: :column, value: Atom.to_string(attribute), datatype: @dt}
    }
  end

  defp specs do
    [
      {Person,
       %Resource{
         ash_resource: Person,
         logical_table: %LogicalTable{table_name: "person"},
         subject_map: %SubjectMap{strategy: :template, value: @ex <> "person-{code}"},
         class_iris: [@s <> "Person"],
         identities: [[:code]],
         predicate_object_maps: [pom(:name, "name"), pom(:rank, "rank")]
       }}
    ]
  end

  defp run(sparql),
    do: AshR2RML.OBDA.query(specs(), sparql, domain: Dom, authorize?: false, allow_unauthorized: true)

  @where "WHERE { ?p <#{@s}name> ?name ; <#{@s}rank> ?rank }"

  test "unmatched SELECT clause with ORDER BY is refused through OBDA.query" do
    assert {:error, error} = run("SELECT?name #{@where} ORDER BY ?rank")
    assert Map.get(error, :code, Map.get(error, :reason)) == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
  end

  test "pure check: unmatched SELECT refused, non-SELECT and no-ORDER-BY untouched" do
    check = &AshR2RML.OBDA.check_order_projected/1
    assert {:error, %AshR2RML.Refusal{}} = check.("SELECT?y WHERE { ?s ?p ?y } ORDER BY ?y")
    assert {:error, %AshR2RML.Refusal{}} = check.("# c\nPREFIX a: <#{@s}>\nSELECT?y WHERE { ?s ?p ?y } ORDER BY ?y")
    assert :ok = check.("ASK{ ?s ?p ?y } ORDER BY ?y")
    assert :ok = check.("SELECT?y WHERE { ?s ?p ?y }")
    assert :ok = check.("SELECT ?y WHERE { ?s ?p ?y } ORDER BY ?y")
  end
end
