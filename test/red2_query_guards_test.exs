# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2QueryGuardsTest do
  @moduledoc """
  Red guards for `QueryBuilder.build_ash_query/3` guard admission and `OBDA.Preflight`:
  custom `Ash.Authorizer` modules count for `require_authorizer`, refusals carry the typed
  `REFUSED_UNAUTHORIZED` / `REFUSED_MISSING_TENANT` codes, and action-level multitenancy
  (`:allow_global` / `:bypass`) is honoured by preflight.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.Preflight
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal

  defmodule CustomAuthorizer do
    @behaviour Ash.Authorizer

    @impl true
    def initial_state(_actor, _resource, _action, _verbose?), do: %{}

    @impl true
    def strict_check_context(_state), do: []

    @impl true
    def strict_check(state, _context), do: {:authorized, state}

    @impl true
    def check_context(_state), do: []

    @impl true
    def check(state, _context), do: {:data, state}
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.Red2QueryGuardsTest.Plain
      resource AshR2RML.Red2QueryGuardsTest.Custom
      resource AshR2RML.Red2QueryGuardsTest.Strict
    end
  end

  defmodule Plain do
    use Ash.Resource,
      domain: AshR2RML.Red2QueryGuardsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Custom do
    use Ash.Resource,
      domain: AshR2RML.Red2QueryGuardsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [AshR2RML.Red2QueryGuardsTest.CustomAuthorizer]

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Strict do
    use Ash.Resource,
      domain: AshR2RML.Red2QueryGuardsTest.Domain,
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

      read :allow_global_read do
        multitenancy(:allow_global)
      end

      read :bypass_read do
        multitenancy(:bypass)
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, public?: true)
    end
  end

  @name_pred "http://schema.org/name"
  @string "http://www.w3.org/2001/XMLSchema#string"

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
      metadata: %{source: :red2_query_guards}
    }
  end

  defp plan, do: %Plan{needed_attributes: [:title]}

  describe "QueryBuilder guards" do
    test "require_authorizer: true admits a resource with a custom Ash.Authorizer" do
      assert {:ok, %Ash.Query{}} =
               QueryBuilder.build_ash_query(mapping(Custom), plan(), require_authorizer: true)
    end

    test "require_authorizer: true without any authorizer is REFUSED_UNAUTHORIZED" do
      assert {:error, %Refusal{code: :REFUSED_UNAUTHORIZED}} =
               QueryBuilder.build_ash_query(mapping(Plain), plan(), require_authorizer: true)
    end

    test "require_tenant: true without a tenant is REFUSED_MISSING_TENANT" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_TENANT}} =
               QueryBuilder.build_ash_query(mapping(Strict), plan(), require_tenant: true)
    end

    test "a strict multitenant resource without any tenant is REFUSED_MISSING_TENANT" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_TENANT}} =
               QueryBuilder.build_ash_query(mapping(Strict), plan(), [])
    end
  end

  describe "Preflight action-level multitenancy" do
    test "strict resource without tenant is refused on the default action" do
      assert {:error, %Refusal{code: :REFUSED_MISSING_TENANT}} = Preflight.check(Strict, [])
    end

    test "an :allow_global read action passes preflight without a tenant" do
      assert :ok = Preflight.check(Strict, action: :allow_global_read)
    end

    test "a :bypass read action passes preflight without a tenant" do
      assert :ok = Preflight.check(Strict, action: :bypass_read)
    end
  end
end
