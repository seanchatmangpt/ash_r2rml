# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2ModifiersTest do
  @moduledoc """
  RED tests for `AshR2RML.QueryBuilder.Modifiers`, driven through `AshR2RML.OBDA.query/3` over
  real `Ash.DataLayer.Ets` rows.

  Findings:

    * ORDER BY over an expression (no LIMIT/OFFSET) must be refused, never silently unsorted.
      CONFLICTS with the doctest on `Modifiers.check/1` that pins
      `ORDER BY STR(?x)` (no LIMIT) as `:ok`.
    * A triple-quoted literal containing a closing brace must not move the modifier tail split.
    * `compare/2` must be antisymmetric even when `inspect/1` collides.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.QueryBuilder.Modifiers

  @s "https://schema.org/"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Red2ModifiersTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource, domain: AshR2RML.Red2ModifiersTest.Dom, data_layer: Ash.DataLayer.Ets

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:code, :name]
      end
    end

    attributes do
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :name, :string, public?: true
    end
  end

  defmodule Opaque do
    defstruct [:id]
  end

  defimpl Inspect, for: Opaque do
    def inspect(_opaque, _opts), do: "#Opaque<>"
  end

  @names ["delta", "alpha", "charlie", "bravo", "echo"]

  setup_all do
    for {name, i} <- Enum.with_index(@names) do
      Ash.create!(Item, %{code: "i#{i}", name: name}, domain: Dom)
    end

    :ok
  end

  defp mapping do
    %Resource{
      ash_resource: Item,
      logical_table: %LogicalTable{table_name: "item"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:item-{code}"},
      class_iris: [@s <> "Thing"],
      identities: [[:code]],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :name,
          predicate_iri: @s <> "name",
          object_map: %ObjectMap{
            strategy: :column,
            value: "name",
            datatype: %Datatype{ash_type: :string, rdf_datatype: @xsd_string}
          }
        }
      ]
    }
  end

  defp run(sparql) do
    AshR2RML.OBDA.query(
      [{Item, mapping()}],
      sparql,
      domain: Dom,
      authorize?: false,
      allow_unauthorized: true
    )
  end

  defp val(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp val(%{value: value}), do: value
  defp val(value), do: value

  defp names(result), do: Enum.map(result.bindings, &val(&1["name"]))

  describe "unparseable ORDER BY" do
    test "ORDER BY over a function call is refused, not silently left unsorted" do
      sparql = "SELECT ?name WHERE { ?i <#{@s}name> ?name } ORDER BY STR(?name)"

      assert {:error, %AshR2RML.Error{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} = run(sparql)
    end

    test "check/1 refuses ORDER BY over an expression without LIMIT" do
      sparql = "SELECT ?x WHERE { ?s ?p ?x } ORDER BY STR(?x)"

      assert {:error, %AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               Modifiers.check(sparql)
    end

    test "supported ORDER BY with LIMIT still sorts and truncates" do
      sparql = "SELECT ?name WHERE { ?i <#{@s}name> ?name } ORDER BY ?name LIMIT 2"

      assert {:ok, result} = run(sparql)
      assert names(result) == ["alpha", "bravo"]
    end
  end

  describe "tail with triple-quoted literal containing a closing brace" do
    test "ORDER BY and LIMIT after the group are still applied" do
      sparql = ~s"""
      SELECT ?name WHERE {
        ?i <#{@s}name> ?name .
        FILTER(?name != \"\"\"a "q" } b\"\"\")
      } ORDER BY DESC(?name) LIMIT 2
      """

      assert {:ok, result} = run(sparql)
      assert names(result) == ["echo", "delta"]
    end
  end

  describe "compare/2 antisymmetry" do
    test "values whose inspect output collides are ordered consistently" do
      a = %Opaque{id: 1}
      b = %Opaque{id: 2}

      assert inspect(a) == inspect(b)
      assert a != b

      forward = Modifiers.compare(a, b)
      backward = Modifiers.compare(b, a)

      assert {forward, backward} in [{:lt, :gt}, {:gt, :lt}]
    end
  end
end
