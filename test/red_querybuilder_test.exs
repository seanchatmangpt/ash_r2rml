# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedQueryBuilderTest do
  @moduledoc """
  Red-before-green courts for audit findings H16 (build_ash_query action/validity) and
  H17 (Lowering kind detection over Ash.Type.NewType).
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  @ex "urn:uuid:"
  @s "http://schema.org/"
  @xsd_integer "http://www.w3.org/2001/XMLSchema#integer"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RedQueryBuilderTest.Item
    end
  end

  defmodule Score do
    use Ash.Type.NewType, subtype_of: :integer
  end

  defmodule Item do
    use Ash.Resource, domain: AshR2RML.RedQueryBuilderTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:code, :plain, :wrapped]
      end
    end

    attributes do
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :plain, :integer, public?: true
      attribute :wrapped, AshR2RML.RedQueryBuilderTest.Score, public?: true
    end
  end

  defp int_dt, do: %Datatype{ash_type: :integer, rdf_datatype: @xsd_integer}

  defp mapping do
    pom = fn attr, pred ->
      %PredicateObjectMap{
        attribute: attr,
        predicate_iri: @s <> pred,
        object_map: %ObjectMap{strategy: :column, value: Atom.to_string(attr), datatype: int_dt()}
      }
    end

    %Resource{
      ash_resource: Item,
      logical_table: %LogicalTable{table_name: "item"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "item-{code}"},
      class_iris: [@s <> "Thing"],
      identities: [[:code]],
      predicate_object_maps: [pom.(:plain, "plain"), pom.(:wrapped, "wrapped")]
    }
  end

  defp valid_query?({:ok, %Ash.Query{valid?: true}}), do: true
  defp valid_query?(_), do: false

  describe "H16 build_ash_query validation" do
    test "H16 control: the primary read action builds a valid query" do
      assert valid_query?(QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom))
    end

    test "H16 an unknown :action is a typed Refusal, not an invalid Ash.Query" do
      result = QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom, action: :no_such_action)
      assert {:error, %Refusal{}} = result
    end

    test "H16 a non-read :action is a typed Refusal, not a query" do
      result = QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom, action: :create)
      assert {:error, %Refusal{}} = result
    end
  end

  describe "H17 NewType kind detection" do
    defp sparql(attr, pred) do
      """
      SELECT ?x WHERE {
        ?e <#{@s}#{pred}> ?x .
        FILTER(?x >= 5)
      } ORDER BY ?x LIMIT 3
      """
      |> tap(fn _ -> attr end)
    end

    test "H17 control: a plain :integer attribute lowers with filter and sort pushed" do
      assert {:ok, pd} = QueryBuilder.lower(sparql(:plain, "plain"), [{Item, mapping()}])
      assert pd.plan.sort == [plain: :asc]
      assert {:gte, :plain, 5} in List.wrap(conditions(pd.plan.filter))
    end

    test "H17 a NewType over :integer lowers exactly like the plain integer" do
      assert {:ok, pd} = QueryBuilder.lower(sparql(:wrapped, "wrapped"), [{Item, mapping()}])
      assert pd.plan.sort == [wrapped: :asc]
      assert {:gte, :wrapped, 5} in List.wrap(conditions(pd.plan.filter))
    end
  end

  defp conditions({:and, list}), do: list
  defp conditions(other), do: other
end
