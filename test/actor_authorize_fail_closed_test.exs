# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ActorAuthorizeFailClosedTest do
  @moduledoc """
  Fail-closed actor/authorize?/tenant/context forwarding through `AshR2RML.OBDA.InMemory`.
  A real ETS resource whose policy requires a present actor AND a context flag proves that
  `actor:`, `authorize:`, `tenant:` and `context:` reach the real `Ash.read!/2` untouched.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.Error
  alias AshR2RML.OBDA.InMemory

  defmodule Gate do
    @moduledoc false
    use Ash.Policy.SimpleCheck

    @impl true
    def describe(_opts), do: "query context carries tag: :go"

    @impl true
    def match?(_actor, ctx, _opts) do
      subject = Map.get(ctx, :query) || Map.get(ctx, :subject)
      context = (subject && subject.context) || %{}
      Map.get(context, :tag) == :go
    end
  end

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.ActorAuthorizeFailClosedTest.Vault
    end
  end

  defmodule Vault do
    use Ash.Resource,
      domain: AshR2RML.ActorAuthorizeFailClosedTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    multitenancy do
      strategy(:attribute)
      attribute(:tenant_id)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    policies do
      policy action_type(:read) do
        forbid_unless(actor_present())
        authorize_if(AshR2RML.ActorAuthorizeFailClosedTest.Gate)
      end
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  @title_pred "http://purl.org/dc/terms/title"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?t WHERE { ?s <#{@title_pred}> ?t }"

  defp mapping do
    %Resource{
      ash_resource: Vault,
      logical_table: %LogicalTable{table_name: "vault"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:{title}", term_type: :iri},
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
      metadata: %{source: :actor_authorize_fail_closed_test}
    }
  end

  setup do
    for tenant <- ["T1", "T2"] do
      Vault
      |> Ash.read!(authorize?: false, tenant: tenant, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false, tenant: tenant, domain: Domain))
    end

    for {tenant, title} <- [{"T1", "secret-one"}, {"T1", "secret-two"}, {"T2", "other"}] do
      Vault
      |> Ash.Changeset.for_create(:create, %{title: title}, tenant: tenant, domain: Domain)
      |> Ash.create!(authorize?: false, tenant: tenant, domain: Domain)
    end

    :ok
  end

  defp subjects(observation), do: observation.rows |> Enum.map(&to_string(&1["s"])) |> Enum.sort()

  # Real Ash errors keep their audited codes instead of a generic SPARQL-feature refusal.
  defp assert_refused(result, code) do
    assert {:error, %Error{code: ^code, resource: Vault} = error} = result
    refute match?({:ok, _}, result)
    error
  end

  test "nil actor with explicit authorize?: true is refused, never rows" do
    result =
      InMemory.query(Vault, mapping(), @select,
        domain: Domain,
        actor: nil,
        authorize?: true,
        tenant: "T1",
        context: %{tag: :go}
      )

    assert_refused(result, :REFUSED_UNAUTHORIZED)
  end

  test "nil actor via materialize is refused, never a graph" do
    assert {:error, %Error{code: :REFUSED_UNAUTHORIZED}} =
             InMemory.materialize(Vault, mapping(),
               domain: Domain,
               actor: nil,
               authorize?: true,
               tenant: "T1",
               context: %{tag: :go}
             )
  end

  test "allowed actor with authorize?: true and context gets exactly the tenant's rows" do
    assert {:ok, obs} =
             InMemory.query(Vault, mapping(), @select,
               domain: Domain,
               actor: %{name: "alice"},
               authorize?: true,
               tenant: "T1",
               context: %{tag: :go}
             )

    assert subjects(obs) == ["urn:uuid:secret-one", "urn:uuid:secret-two"]
  end

  test "actor present but context flag absent is refused (context is not dropped)" do
    result =
      InMemory.query(Vault, mapping(), @select,
        domain: Domain,
        actor: %{name: "alice"},
        authorize?: true,
        tenant: "T1"
      )

    assert_refused(result, :REFUSED_UNAUTHORIZED)
  end

  test "wrong context value is refused" do
    result =
      InMemory.query(Vault, mapping(), @select,
        domain: Domain,
        actor: %{name: "alice"},
        authorize?: true,
        tenant: "T1",
        context: %{tag: :stop}
      )

    assert_refused(result, :REFUSED_UNAUTHORIZED)
  end

  test "tenant is forwarded: T2 sees only T2 rows, never T1's" do
    assert {:ok, obs} =
             InMemory.query(Vault, mapping(), @select,
               domain: Domain,
               actor: %{name: "alice"},
               authorize?: true,
               tenant: "T2",
               context: %{tag: :go}
             )

    assert subjects(obs) == ["urn:uuid:other"]
  end

  test "missing tenant is refused fail-closed even for an allowed actor" do
    result =
      InMemory.query(Vault, mapping(), @select,
        domain: Domain,
        actor: %{name: "alice"},
        authorize?: true,
        context: %{tag: :go}
      )

    assert_refused(result, :REFUSED_MISSING_TENANT)
  end
end
