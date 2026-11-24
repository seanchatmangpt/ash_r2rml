# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryRowPolicyTenantTest do
  @moduledoc """
  Real Ash row-level policy and attribute multitenancy carried through
  `AshR2RML.OBDA.InMemory` (`actor:` / `tenant:` are forwarded verbatim to `Ash.read!/2`).
  Real ETS-backed resources, real Ash authorizer, no doubles.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{Datatype, LogicalTable, ObjectMap, PredicateObjectMap, Resource, SubjectMap}
  alias AshR2RML.OBDA.InMemory

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryRowPolicyTenantTest.Note
      resource AshR2RML.OBDA.InMemoryRowPolicyTenantTest.TenantNote
    end
  end

  defmodule Note do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryRowPolicyTenantTest.Domain,
      data_layer: Ash.DataLayer.Ets,
      authorizers: [Ash.Policy.Authorizer]

    ets do
      private?(true)
    end

    actions do
      defaults([:read, :destroy, create: [:title, :owner]])
    end

    policies do
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

  defmodule TenantNote do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryRowPolicyTenantTest.Domain,
      data_layer: Ash.DataLayer.Ets

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

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
      attribute(:tenant_id, :string, allow_nil?: false, public?: true)
    end
  end

  @title_pred "https://example.org/title"
  @string "http://www.w3.org/2001/XMLSchema#string"

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
      metadata: %{source: :row_policy_tenant_test}
    }
  end

  defp note_mapping, do: mapping(Note, "notes", "https://example.org/notes/{title}")
  defp tenant_mapping, do: mapping(TenantNote, "tenant_notes", "https://example.org/tnotes/{title}")

  @select "SELECT ?s ?t WHERE { ?s <#{@title_pred}> ?t }"

  setup do
    Note
    |> Ash.read!(authorize?: false, domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))

    for tenant <- ["A", "B"] do
      TenantNote
      |> Ash.read!(tenant: tenant, domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, tenant: tenant, domain: Domain))
    end

    :ok
  end

  defp subjects(observation), do: observation.rows |> Enum.map(&to_string(&1["s"])) |> Enum.sort()

  defp subjects_of_graph(graph) do
    graph |> RDF.Graph.triples() |> Enum.map(fn {s, _p, _o} -> to_string(s) end) |> Enum.sort()
  end

  describe "row-level Ash.Policy.Authorizer" do
    setup do
      for {title, owner} <- [{"alpha", "alice"}, {"beta", "alice"}, {"gamma", "bob"}] do
        Note
        |> Ash.Changeset.for_create(:create, %{title: title, owner: owner}, domain: Domain)
        |> Ash.create!(authorize?: false, domain: Domain)
      end

      :ok
    end

    test "each actor sees exactly the rows its policy admits" do
      assert {:ok, alice} = InMemory.query(Note, note_mapping(), @select, domain: Domain, actor: %{name: "alice"})

      assert subjects(alice) == ["https://example.org/notes/alpha", "https://example.org/notes/beta"]

      assert {:ok, bob} = InMemory.query(Note, note_mapping(), @select, domain: Domain, actor: %{name: "bob"})
      assert subjects(bob) == ["https://example.org/notes/gamma"]
    end

    test "an actor owning no rows gets zero bindings" do
      assert {:ok, observation} =
               InMemory.query(Note, note_mapping(), @select, domain: Domain, actor: %{name: "mallory"})

      assert observation.rows == []
    end

    test "materialize graph for alice contains only alice's subjects" do
      assert {:ok, graph} = InMemory.materialize(Note, note_mapping(), domain: Domain, actor: %{name: "alice"})

      assert subjects_of_graph(graph) == ["https://example.org/notes/alpha", "https://example.org/notes/beta"]
    end
  end

  describe "attribute multitenancy" do
    setup do
      for {tenant, titles} <- [{"A", ["a1", "a2"]}, {"B", ["b1"]}], title <- titles do
        TenantNote
        |> Ash.Changeset.for_create(:create, %{title: title}, tenant: tenant, domain: Domain)
        |> Ash.create!(tenant: tenant, domain: Domain)
      end

      :ok
    end

    test "tenant A sees only A's triples, tenant B only B's (query)" do
      assert {:ok, a} = InMemory.query(TenantNote, tenant_mapping(), @select, domain: Domain, tenant: "A")
      assert subjects(a) == ["https://example.org/tnotes/a1", "https://example.org/tnotes/a2"]

      assert {:ok, b} = InMemory.query(TenantNote, tenant_mapping(), @select, domain: Domain, tenant: "B")
      assert subjects(b) == ["https://example.org/tnotes/b1"]
    end

    test "materialize scopes the graph per tenant" do
      assert {:ok, graph_a} = InMemory.materialize(TenantNote, tenant_mapping(), domain: Domain, tenant: "A")
      assert subjects_of_graph(graph_a) == ["https://example.org/tnotes/a1", "https://example.org/tnotes/a2"]

      assert {:ok, graph_b} = InMemory.materialize(TenantNote, tenant_mapping(), domain: Domain, tenant: "B")
      assert subjects_of_graph(graph_b) == ["https://example.org/tnotes/b1"]
    end

    test "no tenant is refused fail-closed (Ash raises TenantRequired; InMemory rescues into a refusal)" do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE, subject: TenantNote} = refusal} =
               InMemory.query(TenantNote, tenant_mapping(), @select, domain: Domain)

      assert refusal.detail =~ "fail-closed"
      assert refusal.evidence.exception =~ "tenant"
    end
  end
end
