# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.AuditRegressionsTest do
  @moduledoc """
  Regression courts for the adversarial audit closure. Real `Ash.DataLayer.Ets` resources
  (see `test/support/audit_regressions/resources.ex`), real Ash policies, real OBDA worker; no
  doubles. Mappings are built as `AshR2RML.Mapping` structs so no module is evaluated with a
  Spark verifier diagnostic.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.AuditRegressions.{Bulk, Domain, Fielded, GraphA, GraphB, Locked, Secretive, TenantScoped}
  alias AshR2RML.Introspection
  alias AshR2RML.Mapping
  alias AshR2RML.Mapping.{Datatype, GraphMap, LogicalTable, ObjectMap, PredicateObjectMap, SubjectMap}
  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.{InMemory, Worker}
  alias AshR2RML.QueryBuilder
  alias AshR2RML.QueryBuilder.Plan
  alias AshR2RML.Refusal
  alias AshR2RML.Security

  @name_iri "https://schema.org/name"
  @thing_iri "https://schema.org/Thing"
  @string_iri "http://www.w3.org/2001/XMLSchema#string"
  @graph_a "urn:uuid:00000000-0000-0000-0000-00000000000a"
  @graph_b "urn:uuid:00000000-0000-0000-0000-00000000000b"
  @sensitive :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION

  # -- fixtures -----------------------------------------------------------------------------

  defp pom(attribute, column, predicate \\ @name_iri) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: predicate,
      object_map: %ObjectMap{
        strategy: :column,
        value: column,
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string_iri}
      }
    }
  end

  defp mapping(resource, opts) do
    %Mapping.Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: Keyword.get(opts, :table, "audit_regressions")},
      subject_map: %SubjectMap{
        strategy: :template,
        value: Keyword.get(opts, :subject, "urn:uuid:{id}"),
        term_type: :iri,
        graph_maps: Keyword.get(opts, :subject_graphs, [])
      },
      class_iris: [@thing_iri],
      predicate_object_maps: Keyword.get(opts, :poms, [pom(:name, "name")]),
      identities: [[:id]],
      metadata: %{}
    }
  end

  defp clear!(resource) do
    resource
    |> Ash.read!(authorize?: false, domain: Domain)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false, domain: Domain))
  end

  defp create!(resource, params) do
    resource
    |> Ash.Changeset.for_create(:create, params, domain: Domain)
    |> Ash.create!(authorize?: false, domain: Domain)
  end

  defp rendered(result), do: inspect(result.bindings, limit: :infinity, printable_limit: :infinity)

  setup do
    for resource <- [GraphA, GraphB, Secretive, Fielded, Locked, Bulk], do: clear!(resource)
    :ok
  end

  # -- 1. named-graph isolation ---------------------------------------------------------------

  describe "named-graph isolation through OBDA.query/3" do
    setup do
      create!(GraphA, %{name: "alpha-in-graph-a"})
      create!(GraphB, %{name: "beta-in-graph-b"})

      specs = [
        {GraphA, mapping(GraphA, subject_graphs: [%GraphMap{strategy: :constant, value: @graph_a}])},
        {GraphB, mapping(GraphB, subject_graphs: [%GraphMap{strategy: :constant, value: @graph_b}])}
      ]

      {:ok, specs: specs}
    end

    test "GRAPH <a> yields only graph a rows and GRAPH <b> only graph b rows", %{specs: specs} do
      query = fn graph -> "SELECT ?s ?n WHERE { GRAPH <#{graph}> { ?s <#{@name_iri}> ?n } }" end

      assert {:ok, a} = OBDA.query(specs, query.(@graph_a), domain: Domain)
      assert {:ok, b} = OBDA.query(specs, query.(@graph_b), domain: Domain)

      assert rendered(a) =~ "alpha-in-graph-a"
      refute rendered(a) =~ "beta-in-graph-b"
      assert rendered(b) =~ "beta-in-graph-b"
      refute rendered(b) =~ "alpha-in-graph-a"
    end

    test "the union default graph still sees both graphs", %{specs: specs} do
      assert {:ok, union} =
               OBDA.query(specs, "SELECT ?n WHERE { ?s <#{@name_iri}> ?n }", domain: Domain)

      assert rendered(union) =~ "alpha-in-graph-a"
      assert rendered(union) =~ "beta-in-graph-b"
    end
  end

  # -- 2. sensitive source column and cloaked attribute fail closed ---------------------------

  describe "sensitive and cloaked attributes in subject and graph maps" do
    test "a sensitive attribute stored under source :db_secret is refused in the subject map" do
      mapping = mapping(Secretive, subject: "urn:uuid:{db_secret}")

      assert {:error, %Refusal{code: @sensitive, evidence: evidence}} =
               Security.admit_in_memory_mapping(Secretive, mapping)

      assert evidence.field == "db_secret"
      assert evidence.where == "subject map"
    end

    test "the same attribute is refused in a graph map by source name and by attribute name" do
      for column <- ["db_secret", "token"] do
        graph = %GraphMap{strategy: :template, value: "urn:uuid:{#{column}}"}
        mapping = mapping(Secretive, subject_graphs: [graph])

        assert {:error, %Refusal{code: @sensitive, evidence: evidence}} =
                 Security.admit_in_memory_mapping(Secretive, mapping)

        assert evidence.field == column
        assert evidence.where == "graph map"
      end
    end

    test "the refusal also surfaces from OBDA.query even with allow_sensitive" do
      mapping = mapping(Secretive, subject: "urn:uuid:{db_secret}")
      create!(Secretive, %{label: "visible", token: "TOKEN-CANARY"})

      # fail closed: the sensitive key is either refused as sensitive or stripped first, which
      # leaves the subject template unresolvable (typed missing-subject refusal); never rows.
      assert {:error, %{code: code}} =
               OBDA.query([{Secretive, mapping}], "SELECT ?n WHERE { ?s <#{@name_iri}> ?n }",
                 domain: Domain,
                 allow_sensitive: true
               )

      assert code in [@sensitive, :REFUSED_MISSING_SUBJECT_MAP]
    end

    test "a cloaked (derived, non-attribute) column cannot key the subject map" do
      mapping = mapping(Secretive, subject: "urn:uuid:{label_plain}")

      assert {:error, %Refusal{code: @sensitive, evidence: evidence}} =
               Security.admit_in_memory_mapping(Secretive, mapping)

      assert evidence.field == "label_plain"
      assert evidence.where == "subject map"
    end

    test "a cloaked column in a graph map is refused or stripped, never carried through" do
      graph = %GraphMap{strategy: :template, value: "urn:uuid:{label_plain}"}
      mapping = mapping(Secretive, subject_graphs: [graph])

      case Security.admit_in_memory_mapping(Secretive, mapping) do
        {:error, %Refusal{code: @sensitive}} ->
          :ok

        {:ok, admitted} ->
          assert admitted.graph_maps == []
          assert admitted.subject_map.graph_maps == []
      end
    end
  end

  # -- 3. attribute multitenancy with a per-tenant identity -----------------------------------

  describe "attribute-multitenant resource with an all_tenants?: false identity" do
    test "Introspection scopes the identity to the tenant attribute" do
      assert Introspection.identities(TenantScoped) == [[:code, :org_id], [:id]]
    end

    test "a subject template without the tenant attribute is not a stable identity" do
      refute Introspection.stable_subject_identity?(TenantScoped, ["code"])
      assert Introspection.stable_subject_identity?(TenantScoped, ["code", "org_id"])
      assert Introspection.stable_subject_identity?(TenantScoped, ["id"])
    end

    test "Mapping.validate refuses the tenant-free template with the identity refusal" do
      mapping =
        TenantScoped
        |> mapping(subject: "urn:uuid:{code}", poms: [pom(:code, "code")])
        |> Map.put(:identities, Introspection.identities(TenantScoped))

      assert {:error, refusals} = Mapping.validate(mapping)
      assert Enum.any?(refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
    end
  end

  # -- 4. field_policy-protected attribute cannot be an oracle --------------------------------

  describe "field_policy-protected attribute through QueryBuilder" do
    setup do
      {:ok,
       mapping: mapping(Fielded, poms: [pom(:title, "title"), pom(:secret, "secret", "https://schema.org/description")])}
    end

    test "filtering on it is refused", %{mapping: mapping} do
      plan = %Plan{needed_attributes: [:title], filter: {:eq, :secret, "guess"}}

      assert {:error, %Refusal{code: @sensitive, evidence: %{attribute: :secret}}} =
               QueryBuilder.build_ash_query(mapping, plan, authorize?: false, allow_unauthorized: true)
    end

    test "sorting on it is refused", %{mapping: mapping} do
      plan = %Plan{needed_attributes: [:title], sort: [{:secret, :asc}]}

      assert {:error, %Refusal{code: @sensitive, evidence: %{attribute: :secret}}} =
               QueryBuilder.build_ash_query(mapping, plan, authorize?: false, allow_unauthorized: true)
    end

    # A `field_policy :*` wildcard covers every attribute, so on `Fielded` all attributes are
    # protected (fail closed); the positive control uses a resource with no field policies.
    test "positive control: an unprotected attribute filters and sorts" do
      mapping = mapping(GraphA, [])
      plan = %Plan{needed_attributes: [:name], filter: {:eq, :name, "t"}, sort: [{:name, :asc}]}

      assert {:ok, %Ash.Query{}} =
               QueryBuilder.build_ash_query(mapping, plan, authorize?: false, allow_unauthorized: true)
    end
  end

  # -- 5. exact refusal codes and bounded reads ------------------------------------------------

  describe "exact codes propagate without a second full read" do
    test "a policy-forbidden read is REFUSED_UNAUTHORIZED and reads no rows" do
      mapping = mapping(Locked, poms: [pom(:title, "title")])

      assert {{:error, failure}, stats} =
               InMemory.query_with_stats(
                 [{Locked, mapping}],
                 "SELECT ?n WHERE { ?s <#{@name_iri}> ?n }",
                 domain: Domain,
                 actor: nil,
                 authorize?: true
               )

      assert {:error, %{code: :REFUSED_UNAUTHORIZED}} = OBDA.normalize_result({:error, failure})
      assert stats.rows_read == 0
    end

    test "REFUSED_TRIPLE_LIMIT_EXCEEDED carries its code and the read stays clamped" do
      total = 6
      for n <- 1..total, do: create!(Bulk, %{name: "bulk-#{n}"})
      mapping = mapping(Bulk, [])
      sparql = "SELECT ?n WHERE { ?s <#{@name_iri}> ?n }"

      assert {{:error, refusal}, stats} =
               InMemory.query_with_stats([{Bulk, mapping}], sparql, domain: Domain, max_triples: 5)

      assert refusal.code == :REFUSED_TRIPLE_LIMIT_EXCEEDED
      assert stats.triples_emitted == 0
      # clamped to div(5, 2) + 1 = 3 rows: never the whole table, and no fallback re-read
      assert stats.rows_read < total

      assert {:error, %{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED}} =
               OBDA.query([{Bulk, mapping}], sparql, domain: Domain, max_triples: 5)
    end
  end

  # -- 6. worker caller chain --------------------------------------------------------------------

  describe "OBDA.Worker propagates $callers" do
    test "the caller is prepended to the inherited chain" do
      inherited = spawn(fn -> :ok end)
      Process.put(:"$callers", [inherited])

      assert {:ok, callers} = Worker.run(fn -> Process.get(:"$callers") end)
      assert callers == [self(), inherited]
    end

    test "an empty chain still names the caller" do
      Process.delete(:"$callers")

      assert {:ok, callers} = Worker.run(fn -> Process.get(:"$callers") end)
      assert callers == [self()]
    end
  end
end
