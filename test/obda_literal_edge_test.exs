# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDALiteralEdgeTest do
  @moduledoc """
  Values with no RDF lexical form (maps, tuples, lists, non-finite decimals) produce a typed
  refusal through `OBDA.query/3`, never a `Protocol.UndefinedError`; ordinary values still emit.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDALiteralEdgeTest.Blob
    end
  end

  defmodule Blob do
    use Ash.Resource,
      domain: AshR2RML.OBDALiteralEdgeTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :value]])
    end

    policies do
      policy always() do
        authorize_if(always())
      end
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.OBDALiteralEdgeTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:value, :term, public?: true)
    end
  end

  @pred "https://schema.org/value"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?o WHERE { ?s <#{@pred}> ?o }"

  defp specs do
    [
      {Blob,
       %Resource{
         ash_resource: Blob,
         logical_table: %LogicalTable{table_name: "blobs"},
         subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{title}", term_type: :iri},
         class_iris: ["https://schema.org/Thing"],
         predicate_object_maps: [
           %PredicateObjectMap{
             attribute: :value,
             predicate_iri: @pred,
             object_map: %ObjectMap{
               strategy: :column,
               value: "value",
               datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
             }
           }
         ],
         identities: [[:title]],
         metadata: %{source: :obda_literal_edge_test}
       }}
    ]
  end

  setup do
    Blob
    |> Ash.read!(authorize?: false, domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))

    :ok
  end

  defp put(value) do
    Blob
    |> Ash.Changeset.for_create(:create, %{title: "t", value: value}, domain: Domain)
    |> Ash.create!(authorize?: false, domain: Domain)
  end

  defp run, do: OBDA.query(specs(), @select, domain: Domain, actor: %{})

  for {label, value} <- [
        map: %{"a" => 1},
        tuple: {:ok, 1},
        charlist: [104, 105],
        nested_list: [1, [2]],
        nan: Decimal.new("NaN"),
        inf: Decimal.new("Infinity"),
        neg_inf: Decimal.new("-Infinity")
      ] do
    test "#{label} value is refused with a typed refusal, not raised" do
      put(unquote(Macro.escape(value)))
      assert {:error, error} = run()
      assert error.code == :REFUSED_NON_LITERAL_DATATYPE
    end
  end

  test "integer, atom and finite decimal still emit literals (positive control)" do
    put(5)
    assert {:ok, %OBDA.Result{bindings: [%{"o" => o}]}} = run()
    assert to_string(o) == "5"
  end

  test "finite decimal emits its plain string form" do
    put(Decimal.new("1.50"))
    assert {:ok, %OBDA.Result{bindings: [%{"o" => o}]}} = run()
    assert to_string(o) == "1.50"
  end
end
