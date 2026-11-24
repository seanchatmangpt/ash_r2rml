# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemorySecurityOptsTest do
  @moduledoc """
  Security options of `AshR2RML.OBDA.InMemory`: default `authorize?: true`, explicit
  `authorize?: false` refused unless `allow_unauthorized: true`, opt-in
  `require_authorizer: true` and `require_tenant: true`. Real ETS resources, no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemorySecurityOptsTest.Guarded
      resource AshR2RML.OBDA.InMemorySecurityOptsTest.Plain
      resource AshR2RML.OBDA.InMemorySecurityOptsTest.Tenanted
    end
  end

  # Policy resource: only actor %{name: "alice"} may read.
  defmodule Guarded do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemorySecurityOptsTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    policies do
      policy action_type(:read) do
        authorize_if(actor_attribute_equals(:name, "alice"))
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Plain do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemorySecurityOptsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  # global?: true lets Ash read without a tenant, so only require_tenant can refuse it.
  defmodule Tenanted do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemorySecurityOptsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(true)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
      global?(true)
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

  @title_pred "https://example.org/title"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?t WHERE { ?s <#{@title_pred}> ?t }"

  defp mapping(resource, table, template) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: table},
      subject_map: %SubjectMap{strategy: :template, value: template, term_type: :iri},
      class_iris: [],
      predicate_object_maps: [
        %PredicateObjectMap{
          attribute: :title,
          predicate_iri: @title_pred,
          object_map: %ObjectMap{
            strategy: :column,
            value: "title",
            datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
          }
        }
      ],
      identities: [[:id]],
      metadata: %{source: :security_opts_test}
    }
  end

  defp guarded_mapping, do: mapping(Guarded, "guarded", "https://example.org/g/{title}")
  defp plain_mapping, do: mapping(Plain, "plain", "https://example.org/p/{title}")
  defp tenant_mapping, do: mapping(Tenanted, "tenanted", "https://example.org/t/{title}")

  defp subjects(observation), do: observation.rows |> Enum.map(&to_string(&1["s"])) |> Enum.sort()

  setup do
    for resource <- [Guarded, Plain] do
      resource
      |> Ash.read!(authorize?: false, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))
    end

    Tenanted |> Ash.read!(domain: Domain) |> Enum.each(&Ash.destroy!(&1, domain: Domain))

    for resource <- [Guarded, Plain] do
      resource
      |> Ash.Changeset.for_create(:create, %{title: "one"}, domain: Domain)
      |> Ash.create!(authorize?: false, domain: Domain)
    end

    Tenanted
    |> Ash.Changeset.for_create(:create, %{title: "t1"}, tenant: "A", domain: Domain)
    |> Ash.create!(tenant: "A", domain: Domain)

    :ok
  end

  describe "authorize? default and explicit false" do
    test "default authorizes: policy admits the allowed actor" do
      assert {:ok, obs} = InMemory.query(Guarded, guarded_mapping(), @select, domain: Domain, actor: %{name: "alice"})
      assert subjects(obs) == ["https://example.org/g/one"]
    end

    test "default authorizes: policy denies another actor (refusal, no rows)" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               InMemory.query(Guarded, guarded_mapping(), @select, domain: Domain, actor: %{name: "mallory"})
    end

    test "explicit authorize?: false is refused without allow_unauthorized" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               InMemory.query(Guarded, guarded_mapping(), @select, domain: Domain, authorize?: false)

      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               InMemory.materialize(Guarded, guarded_mapping(), domain: Domain, authorize?: false)
    end

    test "explicit authorize?: false is refused even on a resource with no authorizer" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               InMemory.query(Plain, plain_mapping(), @select, domain: Domain, authorize?: false)
    end

    test "authorize?: false with allow_unauthorized: true bypasses the policy" do
      assert {:ok, obs} =
               InMemory.query(Guarded, guarded_mapping(), @select,
                 domain: Domain,
                 authorize?: false,
                 allow_unauthorized: true
               )

      assert subjects(obs) == ["https://example.org/g/one"]
    end

    test "authorize?: true explicitly behaves like the default" do
      assert {:ok, obs} =
               InMemory.query(Guarded, guarded_mapping(), @select,
                 domain: Domain,
                 authorize?: true,
                 actor: %{name: "alice"}
               )

      assert subjects(obs) == ["https://example.org/g/one"]
    end
  end

  describe "require_authorizer: true" do
    test "refuses a resource with no Ash.Policy.Authorizer" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, subject: Plain}} =
               InMemory.query(Plain, plain_mapping(), @select, domain: Domain, require_authorizer: true)
    end

    test "admits a resource that has Ash.Policy.Authorizer" do
      assert {:ok, obs} =
               InMemory.query(Guarded, guarded_mapping(), @select,
                 domain: Domain,
                 require_authorizer: true,
                 actor: %{name: "alice"}
               )

      assert subjects(obs) == ["https://example.org/g/one"]
    end

    test "without the option an authorizer-less resource is readable" do
      assert {:ok, obs} = InMemory.query(Plain, plain_mapping(), @select, domain: Domain)
      assert subjects(obs) == ["https://example.org/p/one"]
    end

    test "one authorizer-less spec refuses a whole materialize_many" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               InMemory.materialize_many(
                 [{Guarded, guarded_mapping()}, {Plain, plain_mapping()}],
                 domain: Domain,
                 require_authorizer: true,
                 actor: %{name: "alice"}
               )
    end
  end

  describe "require_tenant: true" do
    test "refuses a multitenant resource queried without tenant" do
      assert {:error, %Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, subject: Tenanted}} =
               InMemory.query(Tenanted, tenant_mapping(), @select, domain: Domain, require_tenant: true)
    end

    test "admits a multitenant resource queried with tenant" do
      assert {:ok, obs} =
               InMemory.query(Tenanted, tenant_mapping(), @select, domain: Domain, require_tenant: true, tenant: "A")

      assert subjects(obs) == ["https://example.org/t/t1"]
    end

    test "does not affect a non-multitenant resource" do
      assert {:ok, obs} = InMemory.query(Plain, plain_mapping(), @select, domain: Domain, require_tenant: true)
      assert subjects(obs) == ["https://example.org/p/one"]
    end

    test "without the option a global multitenant resource reads without tenant" do
      assert {:ok, obs} = InMemory.query(Tenanted, tenant_mapping(), @select, domain: Domain)
      assert subjects(obs) == ["https://example.org/t/t1"]
    end
  end
end
