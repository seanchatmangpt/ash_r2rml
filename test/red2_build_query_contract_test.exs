# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2BuildQueryContractTest do
  @moduledoc """
  Red courts for the QueryBuilder build contract: `{:ok, query} | {:error, _}` (no bare
  `%Ash.Query{}`), Splode errors kept structured, `page: false` on paginated actions and a
  validated `:max_rows`.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  @ex "urn:uuid:"
  @s "http://schema.org/"

  defmodule Dom do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Red2BuildQueryContractTest.Item
    end
  end

  defmodule Item do
    use Ash.Resource, domain: AshR2RML.Red2BuildQueryContractTest.Dom, data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults [:read]

      read :needs_arg do
        argument :must, :string, allow_nil?: false
      end

      read :paged do
        pagination offset?: true, default_limit: 2, required?: false
      end

      create :create do
        primary? true
        accept [:code]
      end
    end

    attributes do
      attribute :code, :string, primary_key?: true, allow_nil?: false, public?: true
    end
  end

  defp mapping do
    %Resource{
      ash_resource: Item,
      logical_table: %LogicalTable{table_name: "item"},
      subject_map: %SubjectMap{strategy: :template, value: @ex <> "item-{code}"},
      class_iris: [@s <> "Thing"],
      identities: [[:code]],
      predicate_object_maps: []
    }
  end

  @bound_codes [:REFUSED_RESOURCE_BOUND, :REFUSED_INVALID_OPTION]

  describe "ok/error contract" do
    test "build_ash_query returns {:ok, valid query}" do
      assert {:ok, %Ash.Query{valid?: true}} =
               QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom)
    end

    test "pushdown_query returns {:ok, valid query}" do
      assert {:ok, %Ash.Query{valid?: true}} =
               QueryBuilder.pushdown_query(Item, mapping(), %Plan{}, domain: Dom)
    end

    test "an invalid built query is {:error, %Refusal{}}" do
      assert {:error, %Refusal{}} =
               QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom, action: :needs_arg)
    end
  end

  describe "ensure_valid keeps Splode structure" do
    test "evidence carries structured errors with class and path, not an inspect string" do
      assert {:error, %Refusal{evidence: evidence}} =
               QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom, action: :needs_arg)

      errors = Map.get(evidence, :errors)
      assert is_list(errors) and errors != []

      for err <- errors do
        assert is_map(err)
        assert Map.has_key?(err, :class)
        assert Map.has_key?(err, :path)
      end
    end
  end

  describe "page: false" do
    test "a paginated read action yields a plain list bounded by max_rows" do
      for code <- ~w(a b c d e) do
        Item |> Ash.Changeset.for_create(:create, %{code: code}) |> Ash.create!(domain: Dom)
      end

      assert {:ok, query} =
               QueryBuilder.build_ash_query(mapping(), %Plan{},
                 domain: Dom,
                 action: :paged,
                 max_rows: 10
               )

      result = Ash.read!(query, domain: Dom)
      assert is_list(result)
      assert length(result) == 5
    end
  end

  describe "max_rows validation" do
    for bad <- [nil, 0, -1, "5", 1.5] do
      test "max_rows #{inspect(bad)} is a typed refusal, not an ArithmeticError" do
        result =
          QueryBuilder.build_ash_query(mapping(), %Plan{}, domain: Dom, max_rows: unquote(bad))

        assert {:error, %Refusal{code: code}} = result
        assert code in @bound_codes
      end

      test "pushdown_query max_rows #{inspect(bad)} is a typed refusal" do
        result =
          QueryBuilder.pushdown_query(Item, mapping(), %Plan{}, domain: Dom, max_rows: unquote(bad))

        assert {:error, %Refusal{code: code}} = result
        assert code in @bound_codes
      end
    end
  end
end
