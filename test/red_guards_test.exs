# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RedGuardsTest do
  @moduledoc """
  Red-before-green guards: policy-pruned resources must not skip `require_tenant` (H15), and
  `QueryBuilder.build_ash_query/3` must apply the same guard options as `OBDA.InMemory` (H18).
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RedGuardsTest.Locked
      resource AshR2RML.RedGuardsTest.Open
      resource AshR2RML.RedGuardsTest.Scoped
    end
  end

  # Global multitenant resource whose policy forbids every read: always policy-pruned.
  defmodule Locked do
    use Ash.Resource,
      domain: AshR2RML.RedGuardsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(false)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
      global?(true)
    end

    policies do
      policy always() do
        forbid_if always()
      end
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, public?: true)
    end
  end

  defmodule Open do
    use Ash.Resource,
      domain: AshR2RML.RedGuardsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.RedGuardsTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Scoped do
    use Ash.Resource,
      domain: AshR2RML.RedGuardsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, public?: true)
    end
  end

  @name_pred "http://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?o WHERE { ?s <#{@name_pred}> ?o }"

  defp mapping(resource) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: "titles"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:title-{title}", term_type: :iri},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @name_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "title",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:title]],
      metadata: %{source: :red_guards}
    }
  end

  defp plan, do: %Plan{needed_attributes: [:title]}

  describe "H15 policy pruning vs guards" do
    test "H15 require_tenant: true refuses a policy-pruned global multitenant resource without tenant" do
      result = OBDA.query([{Locked, mapping(Locked)}], @select, domain: Domain, require_tenant: true)

      assert {:error, _refusal} = result
    end
  end

  describe "H18 QueryBuilder guards" do
    test "H18 authorize?: false without allow_unauthorized is refused" do
      result = QueryBuilder.build_ash_query(mapping(Open), plan(), authorize?: false)

      refute match?(%Ash.Query{}, result)
      assert {:error, %Refusal{}} = result
    end

    test "H18 authorize?: false with allow_unauthorized: true builds a query" do
      result =
        QueryBuilder.build_ash_query(mapping(Open), plan(), authorize?: false, allow_unauthorized: true)

      assert {:ok, %Ash.Query{}} = result
    end

    test "H18 require_authorizer: true refuses a resource without an authorizer" do
      result = QueryBuilder.build_ash_query(mapping(Open), plan(), require_authorizer: true)

      refute match?(%Ash.Query{}, result)
      assert {:error, %Refusal{}} = result
    end

    test "H18 require_tenant: true refuses a multitenant resource without a tenant" do
      result = QueryBuilder.build_ash_query(mapping(Scoped), plan(), require_tenant: true)

      refute match?(%Ash.Query{}, result)
      assert {:error, %Refusal{}} = result
    end

    test "H18 require_tenant: true admits a multitenant resource when a tenant is given" do
      result =
        QueryBuilder.build_ash_query(mapping(Scoped), plan(), require_tenant: true, tenant: "A")

      assert {:ok, %Ash.Query{}} = result
    end
  end
end
