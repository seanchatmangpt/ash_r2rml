# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.MoneyProjectionTest do
  @moduledoc """
  Composite monetary projection: a money value is decomposed into an exact `xsd:decimal`
  amount literal plus a currency IRI. Lexical forms are exact (no float coercion, scale
  preserved), and unsupported composite shapes are typed refusals, never opaque literals.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal

  @subject_prefix "urn:uuid:"
  @class "https://schema.org/PriceSpecification"
  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"
  @amount "https://schema.org/price"
  @currency "https://schema.org/priceCurrency"
  @iso "https://spec.edmcouncil.org/fibo/ontology/FND/Accounting/CurrencyAmount/"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.MoneyProjectionTest.Price
    end
  end

  defmodule Price do
    use Ash.Resource, domain: AshR2RML.MoneyProjectionTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private? false
    end

    actions do
      defaults [:read]

      create :create do
        primary? true
        accept [:key, :amount, :currency]
      end
    end

    attributes do
      attribute :key, :string, primary_key?: true, allow_nil?: false, public?: true
      attribute :amount, :decimal, public?: true
      attribute :currency, :string, public?: true
    end
  end

  defmodule MoneyMap do
    use Ash.Type.NewType, subtype_of: :map
  end

  @cases [
    {"trailing_zero", "0.10", "0.10"},
    {"two_places", "12.50", "12.50"},
    {"tiny_scale", "0.000000001", "0.000000001"},
    {"tiny_exponent", "1E-9", "0.000000001"},
    {"large", "123456789012345678901234567890.12", "123456789012345678901234567890.12"},
    {"zero", "0", "0"},
    {"zero_scaled", "0.00", "0.00"},
    {"negative", "-12.50", "-12.50"},
    {"negative_tiny", "-0.000000001", "-0.000000001"}
  ]

  setup_all do
    Ash.DataLayer.Ets.stop(Price)

    for {key, amount, _expected} <- @cases do
      Price
      |> Ash.Changeset.for_create(
        :create,
        %{key: key, amount: Decimal.new(amount), currency: "EUR"},
        domain: Dom
      )
      |> Ash.create!(domain: Dom)
    end

    # A float-sourced amount: Ash casts it to a Decimal; it must not leak binary expansion.
    Price
    |> Ash.Changeset.for_create(:create, %{key: "float_src", amount: 0.1, currency: "USD"}, domain: Dom)
    |> Ash.create!(domain: Dom)

    :ok
  end

  defp amount_pom do
    %PredicateObjectMap{
      attribute: :amount,
      predicate_iri: @amount,
      object_map: %ObjectMap{
        strategy: :column,
        value: "amount",
        datatype: %Datatype{ash_type: Ash.Type.Decimal, rdf_datatype: @xsd_decimal}
      }
    }
  end

  defp currency_pom do
    %PredicateObjectMap{
      attribute: :currency,
      predicate_iri: @currency,
      object_map: %ObjectMap{strategy: :template, value: @iso <> "{currency}", term_type: :iri}
    }
  end

  defp mapping(poms) do
    %Resource{
      ash_resource: Price,
      logical_table: %LogicalTable{table_name: "prices"},
      subject_map: %SubjectMap{strategy: :template, value: @subject_prefix <> "{key}"},
      class_iris: [@class],
      identities: [[:key]],
      predicate_object_maps: poms
    }
  end

  defp objects(graph, subject_key, predicate) do
    subject = RDF.iri(@subject_prefix <> subject_key)

    graph
    |> RDF.Graph.triples()
    |> Enum.filter(fn {s, p, _o} -> s == subject and to_string(p) == predicate end)
    |> Enum.map(fn {_s, _p, o} -> o end)
  end

  defp materialize!(poms) do
    assert {:ok, graph} = InMemory.materialize(Price, mapping(poms), domain: Dom)
    graph
  end

  describe "amount lexical exactness" do
    for {key, input, expected} <- @cases do
      test "#{key}: #{input} projects as xsd:decimal #{expected}" do
        graph = materialize!([amount_pom()])

        assert [%RDF.Literal{} = lit] = objects(graph, unquote(key), @amount)
        assert RDF.Literal.lexical(lit) == unquote(expected)
        assert to_string(RDF.Literal.datatype_id(lit)) == @xsd_decimal
      end
    end

    test "float-sourced 0.1 is the exact decimal 0.1, not a binary expansion" do
      graph = materialize!([amount_pom()])

      assert [%RDF.Literal{} = lit] = objects(graph, "float_src", @amount)
      assert RDF.Literal.lexical(lit) == "0.1"
      refute String.contains?(RDF.Literal.lexical(lit), "000000000000000055")
    end

    test "no amount lexical form uses exponent notation" do
      graph = materialize!([amount_pom()])

      lexicals =
        graph
        |> RDF.Graph.triples()
        |> Enum.filter(fn {_s, p, _o} -> to_string(p) == @amount end)
        |> Enum.map(fn {_s, _p, o} -> RDF.Literal.lexical(o) end)

      assert length(lexicals) == length(@cases) + 1
      refute Enum.any?(lexicals, &String.match?(&1, ~r/[eE]/))
    end
  end

  describe "currency IRI" do
    test "currency projects as an IRI object, never a literal" do
      graph = materialize!([amount_pom(), currency_pom()])

      assert [%RDF.IRI{} = eur] = objects(graph, "negative", @currency)
      assert to_string(eur) == @iso <> "EUR"
      assert [%RDF.IRI{} = usd] = objects(graph, "float_src", @currency)
      assert to_string(usd) == @iso <> "USD"
    end

    test "a literal-typed currency template is a typed refusal" do
      pom = put_in(currency_pom().object_map.term_type, :literal)

      assert {:error, %Refusal{code: :UNSUPPORTED_TERM_TYPE}} =
               InMemory.materialize(Price, mapping([amount_pom(), pom]), domain: Dom)
    end
  end

  describe "money types in the registry" do
    test "an AshMoney-style money type resolves to xsd:decimal with decimal storage" do
      assert AshR2RML.Money.money_type?(AshMoney.Types.Money)

      assert {:ok, %Datatype{rdf_datatype: @xsd_decimal, storage_type: :decimal}} =
               Registry.resolve(AshMoney.Types.Money)

      assert Registry.supported?(AshMoney.Types.Money)
    end

    test "Money.project emits an xsd:decimal amount and a public currency IRI" do
      assert {:ok, node} = AshR2RML.Money.project(Decimal.new("12.50"), currency: "eur")
      assert node.amount == {:literal, "12.50", @xsd_decimal}
      assert node.currency_iri == @iso <> "EUR"
      assert node.class_iri == AshR2RML.Money.monetary_amount_class()
    end

    test "non-finite decimals are refused" do
      assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} = AshR2RML.Money.project(Decimal.new("NaN"))
      assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} = AshR2RML.Money.project(Decimal.new("Infinity"))
    end

    test "a relative currency_base_iri is refused, an absolute one is honoured" do
      assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} =
               AshR2RML.Money.project(Decimal.new("1"), currency: "USD", currency_base_iri: "currencies/")

      assert {:ok, %{currency_iri: "urn:uuid:USD"}} =
               AshR2RML.Money.project(Decimal.new("1"), currency: "USD", currency_base_iri: "urn:uuid:")
    end
  end

  describe "unsupported composites are refused" do
    test "a raw :map money composite has no admitted datatype" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:map)
      refute Registry.supported?(:map)
    end

    test "a NewType money map is refused, not stringified" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(MoneyMap)
      refute Registry.supported?(MoneyMap)
    end

    test "keyword and tuple composites are refused" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:keyword)
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:tuple)
    end
  end
end
