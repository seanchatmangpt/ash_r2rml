# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ObdaOrderUnprojectedTest do
  @moduledoc """
  ORDER BY over a variable the SELECT does not project is refused loudly through
  `AshR2RML.OBDA.query/3` (real `Ash.DataLayer.Ets` rows); it is never silently ignored.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}

  @ex "https://ex.test/"
  @s "https://schema.test/"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ObdaOrderUnprojectedTest.Person
    end
  end

  defmodule Person do
    use Ash.Resource, domain: AshR2RML.ObdaOrderUnprojectedTest.Dom, data_layer: Ash.DataLayer.Ets

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
         subject_map: %SubjectMap{strategy: :template, value: @ex <> "person/{code}"},
         class_iris: [@ex <> "Person"],
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

  defp names(result), do: Enum.map(result.bindings, &val(&1["name"]))

  defp code_of({:error, %{code: code}}), do: code
  defp code_of({:error, %{reason: code}}), do: code

  test "ORDER BY an unprojected variable is refused, not ignored" do
    result = run("SELECT ?name WHERE { ?p <#{@s}name> ?name ; <#{@s}rank> ?rank } ORDER BY ?rank")

    assert {:error, _} = result
    assert code_of(result) == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
  end

  test "DESC() over an unprojected variable is refused" do
    assert {:error, _} = run("SELECT ?name WHERE { ?p <#{@s}name> ?name ; <#{@s}rank> ?rank } ORDER BY DESC(?rank)")
  end

  test "ORDER BY a projected variable is honored" do
    assert {:ok, result} = run("SELECT ?name ?rank WHERE { ?p <#{@s}name> ?name ; <#{@s}rank> ?rank } ORDER BY ?rank")
    assert names(result) == ["bob", "alice", "carol"]
  end

  test "SELECT * projects every variable so ORDER BY is honored" do
    assert {:ok, result} = run("SELECT * WHERE { ?p <#{@s}name> ?name ; <#{@s}rank> ?rank } ORDER BY DESC(?rank)")
    assert names(result) == ["carol", "alice", "bob"]
  end

  test "check_order_projected/1 is pure" do
    assert :ok = AshR2RML.OBDA.check_order_projected("SELECT ?a WHERE { ?s ?p ?a } ORDER BY ?a")
    assert :ok = AshR2RML.OBDA.check_order_projected("SELECT ?a WHERE { ?s ?p ?a }")
    assert {:error, _} = AshR2RML.OBDA.check_order_projected("SELECT ?a WHERE { ?s ?p ?a . ?s ?q ?b } ORDER BY ?b")
  end
end
