# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW7OrderProjectedTest do
  @moduledoc """
  ORDER BY a variable that only occurs inside a SELECT expression is refused through
  `AshR2RML.OBDA.query/3`; aliases, bare variables and `SELECT *` stay projected.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @ex "urn:uuid:"
  @s "http://schema.org/"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW7OrderProjectedTest.Person
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.RefactorW7OrderProjectedTest.Dom,
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
      identity :by_code, [:code], pre_check_with: AshR2RML.RefactorW7OrderProjectedTest.Dom
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

  defp val(%RDF.Literal{} = l), do: RDF.Literal.value(l)
  defp val(%{value: v}), do: v
  defp val(v), do: v

  @where "WHERE { ?p <#{@s}name> ?name ; <#{@s}rank> ?rank }"

  test "ORDER BY a variable only inside a SELECT expression is refused" do
    result = run("SELECT (STR(?rank) AS ?r) ?name #{@where} ORDER BY ?rank")

    assert {:error, error} = result
    assert Map.get(error, :code, Map.get(error, :reason)) == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
  end

  test "pure check: expression-only variable unprojected, alias and bare projected" do
    check = &AshR2RML.OBDA.check_order_projected/1
    assert {:error, _} = check.("SELECT (STR(?y) AS ?x) WHERE { ?s ?p ?y } ORDER BY ?y")
    assert :ok = check.("SELECT (STR(?y) AS ?x) WHERE { ?s ?p ?y } ORDER BY ?x")
    assert :ok = check.("SELECT ?y (STR(?y) AS ?x) WHERE { ?s ?p ?y } ORDER BY ?y")
    assert :ok = check.("SELECT * WHERE { ?s ?p ?y } ORDER BY ?y")
  end

  test "ORDER BY a bare projected variable is honored" do
    assert {:ok, result} = run("SELECT ?name ?rank #{@where} ORDER BY ?rank")
    assert Enum.map(result.bindings, &val(&1["name"])) == ["bob", "alice", "carol"]
  end

  test "SELECT * keeps every variable projected" do
    assert {:ok, result} = run("SELECT * #{@where} ORDER BY DESC(?rank)")
    assert Enum.map(result.bindings, &val(&1["name"])) == ["carol", "alice", "bob"]
  end

  test "ORDER BY an alias is not refused as unprojected" do
    case run("SELECT ?name (STR(?rank) AS ?r) #{@where} ORDER BY ?r") do
      {:ok, _} -> :ok
      {:error, error} -> refute inspect(error) =~ "not projected by the SELECT"
    end
  end

  test "COUNT(*) in the select list does not disable the unprojected ORDER BY refusal" do
    sparql = "SELECT (COUNT(*) AS ?c) WHERE { ?s ?p ?o } ORDER BY ?o"
    assert {:error, %AshR2RML.Refusal{}} = AshR2RML.OBDA.check_order_projected(sparql)
  end
end
