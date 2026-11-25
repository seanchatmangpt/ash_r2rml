# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.QueryBuilderTest do
  @moduledoc """
  Built queries are executed with `Ash.read` against real ETS-backed resources; assertions are
  on the rows actually returned.
  """

  use ExUnit.Case, async: false

  doctest AshR2RML.QueryBuilder

  alias AshR2RML.Mapping.{LogicalTable, Resource, SubjectMap}
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.QueryBuilderTest.Org
      resource AshR2RML.QueryBuilderTest.Person
      resource AshR2RML.QueryBuilderTest.TenantDoc
      resource AshR2RML.QueryBuilderTest.OwnedDoc
    end
  end

  defmodule Org do
    use Ash.Resource,
      domain: AshR2RML.QueryBuilderTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, create: [:name]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.QueryBuilderTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, create: [:name, :age, :secret, :org_id]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:age, :integer, public?: true)
      attribute(:secret, :string, public?: true, sensitive?: true)
    end

    relationships do
      belongs_to(:org, AshR2RML.QueryBuilderTest.Org, public?: true)
    end
  end

  defmodule TenantDoc do
    use Ash.Resource,
      domain: AshR2RML.QueryBuilderTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read, create: [:title]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule OwnedDoc do
    use Ash.Resource,
      domain: AshR2RML.QueryBuilderTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    actions do
      defaults([:read, create: [:title, :owner]])
    end

    policies do
      policy action_type([:read, :create]) do
        authorize_if(always())
      end

      policy action_type(:read) do
        authorize_if(expr(owner == ^actor(:name)))
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:owner, :string, allow_nil?: false, public?: true)
    end
  end

  defp mapping(resource, template) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: "t"},
      subject_map: %SubjectMap{strategy: :template, value: template, term_type: :iri},
      class_iris: ["https://schema.org/Thing"],
      identities: [[:id]]
    }
  end

  defp person_mapping, do: mapping(Person, "urn:uuid:{name}")

  defp create!(resource, params, opts \\ []) do
    resource
    |> Ash.Changeset.for_create(:create, params, opts)
    |> Ash.create!(Keyword.put(opts, :authorize?, false))
  end

  defp seed_people do
    org = create!(Org, %{name: "Acme"})

    for {name, age} <- [{"alice", 30}, {"bob", 25}, {"carol", 41}, {"dave", 25}, {"alina", 19}] do
      create!(Person, %{name: name, age: age, secret: "s-#{name}", org_id: org.id})
    end

    org
  end

  defp run(plan, opts \\ []) do
    assert {:ok, %Ash.Query{} = query} =
             QueryBuilder.build_ash_query(person_mapping(), plan, Keyword.put_new(opts, :domain, Domain))

    Ash.read!(query)
  end

  defp names(rows), do: rows |> Enum.map(& &1.name) |> Enum.sort()

  setup do
    seed_people()
    :ok
  end

  describe "filter pushdown" do
    test "comparison operators return exactly the matching rows" do
      assert names(run(%Plan{needed_attributes: [:name, :age], filter: {:eq, :age, 25}})) == ["bob", "dave"]
      assert names(run(%Plan{needed_attributes: [:age], filter: {:neq, :age, 25}})) == ["alice", "alina", "carol"]
      assert names(run(%Plan{needed_attributes: [:age], filter: {:lt, :age, 25}})) == ["alina"]
      assert names(run(%Plan{needed_attributes: [:age], filter: {:lte, :age, 25}})) == ["alina", "bob", "dave"]
      assert names(run(%Plan{needed_attributes: [:age], filter: {:gt, :age, 30}})) == ["carol"]
      assert names(run(%Plan{needed_attributes: [:age], filter: {:gte, :age, 30}})) == ["alice", "carol"]
    end

    test "string functions CONTAINS / STRSTARTS / STRENDS" do
      assert names(run(%Plan{filter: {:contains, :name, "li"}})) == ["alice", "alina"]
      assert names(run(%Plan{filter: {:strstarts, :name, "ali"}})) == ["alice", "alina"]
      assert names(run(%Plan{filter: {:strends, :name, "e"}})) == ["alice", "dave"]
    end

    test "conjunction and disjunction" do
      conj = {:and, [{:strstarts, :name, "ali"}, {:gt, :age, 20}]}
      assert names(run(%Plan{needed_attributes: [:age], filter: conj})) == ["alice"]

      disj = {:or, [{:eq, :name, "bob"}, {:eq, :name, "carol"}]}
      assert names(run(%Plan{filter: disj})) == ["bob", "carol"]
    end
  end

  describe "sort, offset, limit" do
    test "sort + offset + limit page the ordered result" do
      plan = %Plan{needed_attributes: [:age], sort: [{:age, :desc}, {:name, :asc}], offset: 1, limit: 2}
      assert Enum.map(run(plan), & &1.name) == ["alice", "bob"]
    end

    test "limit is capped at max_rows + 1 so overflow is detectable" do
      assert length(run(%Plan{}, max_rows: 2)) == 3
      assert length(run(%Plan{limit: 1}, max_rows: 2)) == 1
      assert length(run(%Plan{limit: 100}, max_rows: 2)) == 3
      assert length(run(%Plan{})) == 5
    end
  end

  describe "select and load" do
    test "selects subject and needed attributes only, never sensitive ones" do
      [row | _] = run(%Plan{needed_attributes: [:age]})
      assert is_binary(row.name)
      assert is_integer(row.age)
      assert %Ash.NotLoaded{} = row.secret
    end

    test "unneeded attributes are not selected" do
      [row | _] = run(%Plan{})
      assert %Ash.NotLoaded{} = row.age
    end

    test "loads only the needed relationships" do
      [with_org | _] = run(%Plan{needed_relationships: [:org]})
      assert %Org{name: "Acme"} = with_org.org

      [without_org | _] = run(%Plan{})
      assert %Ash.NotLoaded{} = without_org.org
    end
  end

  describe "refusals" do
    test "sensitive attribute is refused for select, filter and sort" do
      for plan <- [
            %Plan{needed_attributes: [:secret]},
            %Plan{filter: {:eq, :secret, "s-bob"}},
            %Plan{sort: [{:secret, :asc}]}
          ] do
        assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} =
                 QueryBuilder.build_ash_query(person_mapping(), plan, domain: Domain)
      end
    end

    test "unknown attribute, relationship and filter shape" do
      assert {:error, %Refusal{code: :REFUSED_UNKNOWN_ATTRIBUTE}} =
               QueryBuilder.build_ash_query(person_mapping(), %Plan{needed_attributes: [:nope]}, domain: Domain)

      assert {:error, %Refusal{code: :REFUSED_AMBIGUOUS_RELATIONSHIP}} =
               QueryBuilder.build_ash_query(person_mapping(), %Plan{needed_relationships: [:nope]}, domain: Domain)

      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               QueryBuilder.build_ash_query(person_mapping(), %Plan{filter: {:regex, :name, "a"}}, domain: Domain)
    end
  end

  describe "tenant and actor" do
    test "tenant scopes the read" do
      for {tenant, title} <- [{"A", "a-doc"}, {"B", "b-doc"}] do
        create!(TenantDoc, %{title: title}, tenant: tenant)
      end

      mapping = mapping(TenantDoc, "urn:uuid:{id}")

      assert {:ok, query} =
               QueryBuilder.build_ash_query(mapping, %Plan{needed_attributes: [:title]},
                 tenant: "A",
                 domain: Domain
               )

      assert Enum.map(Ash.read!(query), & &1.title) == ["a-doc"]
    end

    test "actor policy is enforced on the built query (authorize? true)" do
      create!(OwnedDoc, %{title: "mine", owner: "me"})
      create!(OwnedDoc, %{title: "theirs", owner: "them"})

      mapping = mapping(OwnedDoc, "urn:uuid:{id}")

      assert {:ok, query} =
               QueryBuilder.build_ash_query(mapping, %Plan{needed_attributes: [:title]},
                 actor: %{name: "me"},
                 domain: Domain
               )

      assert Enum.map(Ash.read!(query), & &1.title) == ["mine"]
    end
  end
end
