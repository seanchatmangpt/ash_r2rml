# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RefactorW9GuardTestsTest do
  @moduledoc """
  Real-collaborator tests that fail when a guard is removed: the reference-pass triple bound,
  the SPARQL protocol option allowlist, the graph-map sensitivity check reached through
  `InMemory.materialize/3`, and `require_authorizer` / `require_tenant` forwarding by `OBDA.query/3`.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Mapping.{
    Datatype,
    GraphMap,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.OBDA
  alias AshR2RML.OBDA.InMemory
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.Protocol

  defmodule Domain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.RefactorW9GuardTestsTest.Node
      resource AshR2RML.RefactorW9GuardTestsTest.Person
      resource AshR2RML.RefactorW9GuardTestsTest.Plain
      resource AshR2RML.RefactorW9GuardTestsTest.Tenanted
    end
  end

  defmodule Node do
    use Ash.Resource,
      domain: AshR2RML.RefactorW9GuardTestsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:code, :parent_code, :label]])
    end

    identities do
      identity(:by_code, [:code], pre_check_with: AshR2RML.RefactorW9GuardTestsTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:code, :string, allow_nil?: false, public?: true)
      attribute(:parent_code, :string, public?: true)
      attribute(:label, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Person do
    use Ash.Resource,
      domain: AshR2RML.RefactorW9GuardTestsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:name, :ssn]])
    end

    identities do
      identity(:by_name, [:name], pre_check_with: AshR2RML.RefactorW9GuardTestsTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:name, :string, allow_nil?: false, public?: true)
      attribute(:ssn, :string, allow_nil?: false, public?: true, sensitive?: true)
    end
  end

  defmodule Plain do
    use Ash.Resource,
      domain: AshR2RML.RefactorW9GuardTestsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
    end

    actions do
      defaults([:read, :destroy, create: [:title]])
    end

    identities do
      identity(:by_title, [:title], pre_check_with: AshR2RML.RefactorW9GuardTestsTest.Domain)
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, allow_nil?: false, public?: true)
    end
  end

  defmodule Tenanted do
    use Ash.Resource,
      domain: AshR2RML.RefactorW9GuardTestsTest.Domain,
      data_layer: Ash.DataLayer.Ets

    ets do
      private?(false)
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

  @name_pred "http://schema.org/name"
  @parent_pred "http://schema.org/parent"
  @string "http://www.w3.org/2001/XMLSchema#string"
  @select "SELECT ?s ?o WHERE { ?s <#{@name_pred}> ?o }"

  defp name_map(attribute, column) do
    %PredicateObjectMap{
      attribute: attribute,
      predicate_iri: @name_pred,
      object_map: %ObjectMap{
        strategy: :column,
        value: column,
        datatype: %Datatype{ash_type: Ash.Type.String, rdf_datatype: @string}
      }
    }
  end

  defp node_mapping do
    %Resource{
      ash_resource: Node,
      logical_table: %LogicalTable{table_name: "nodes"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:node-{code}", term_type: :iri},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: [name_map(:label, "label")],
      reference_object_maps: [
        %ReferenceObjectMap{
          relationship: :parent,
          predicate_iri: @parent_pred,
          parent_resource: Node,
          joins: [%JoinCondition{child: "parent_code", parent: "code"}]
        }
      ],
      identities: [[:code]],
      metadata: %{source: :w9_guard_tests}
    }
  end

  defp person_mapping(graph_maps) do
    %Resource{
      ash_resource: Person,
      logical_table: %LogicalTable{table_name: "people"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:person-{name}", term_type: :iri},
      class_iris: ["http://schema.org/Thing"],
      graph_maps: graph_maps,
      predicate_object_maps: [name_map(:name, "name")],
      identities: [[:name]],
      metadata: %{source: :w9_guard_tests}
    }
  end

  defp title_mapping(resource) do
    %Resource{
      ash_resource: resource,
      logical_table: %LogicalTable{table_name: "titles"},
      subject_map: %SubjectMap{strategy: :template, value: "urn:uuid:title-{title}", term_type: :iri},
      class_iris: ["http://schema.org/Thing"],
      predicate_object_maps: [name_map(:title, "title")],
      identities: [[:title]],
      metadata: %{source: :w9_guard_tests}
    }
  end

  setup do
    for resource <- [Node, Person, Plain] do
      resource
      |> Ash.read!(domain: Domain)
      |> Enum.each(&Ash.destroy!(&1, domain: Domain))
    end

    Tenanted |> Ash.read!(domain: Domain) |> Enum.each(&Ash.destroy!(&1, domain: Domain))

    for code <- ["n1", "n2"] do
      Node
      |> Ash.Changeset.for_create(:create, %{code: code, parent_code: code, label: "L-#{code}"}, domain: Domain)
      |> Ash.create!(domain: Domain)
    end

    Person
    |> Ash.Changeset.for_create(:create, %{name: "ada", ssn: "123-45-6789"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    Plain
    |> Ash.Changeset.for_create(:create, %{title: "one"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    Tenanted
    |> Ash.Changeset.for_create(:create, %{title: "t1"}, tenant: "A", domain: Domain)
    |> Ash.create!(tenant: "A", domain: Domain)

    :ok
  end

  describe "reference-pass max_triples bound" do
    test "refuses when reference triples push emitted past max_triples after the base pass passed" do
      # base pass: 2 name triples (<= 3); reference pass adds 1 per row -> 4 > 3.
      assert {:error, %Refusal{code: :REFUSED_TRIPLE_LIMIT_EXCEEDED} = refusal} =
               InMemory.materialize(Node, node_mapping(), domain: Domain, max_triples: 3)

      assert refusal.evidence.limit == 3
    end

    test "a generous max_triples admits the same mapping" do
      assert {:ok, graph} = InMemory.materialize(Node, node_mapping(), domain: Domain, max_triples: 1_000)
      assert RDF.Graph.triple_count(graph) > 3
    end
  end

  describe "SPARQL.Protocol option allowlist" do
    test "an unknown option is refused with the unknown key in evidence (endpoint never contacted)" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT} = refusal} =
               Protocol.query("http://93.184.216.34/sparql", @select, bogus_option: true)

      assert refusal.evidence.unknown_options == [:bogus_option]
    end

    test "accepted options pass validation and reach the endpoint guard instead" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT} = refusal} =
               Protocol.query("http://127.0.0.1:9/sparql", @select, timeout: 100, max_rows: 1)

      refute Map.has_key?(refusal.evidence, :unknown_options)
    end
  end

  describe "graph-map sensitivity through InMemory.materialize" do
    test "a sensitive attribute as a column graph map is refused" do
      mapping = person_mapping([%GraphMap{strategy: :column, value: "ssn"}])

      assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} =
               InMemory.materialize(Person, mapping, domain: Domain)
    end

    test "a sensitive attribute inside a template graph map is refused" do
      mapping = person_mapping([%GraphMap{strategy: :template, value: "http://schema.org/graph/{ssn}"}])

      assert {:error, %Refusal{code: :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION}} =
               InMemory.materialize(Person, mapping, domain: Domain)
    end

    test "allow_sensitive: true admits the same graph map" do
      mapping = person_mapping([%GraphMap{strategy: :template, value: "http://schema.org/graph/{ssn}"}])

      assert {:ok, %RDF.Graph{}} = InMemory.materialize(Person, mapping, domain: Domain, allow_sensitive: true)
    end
  end

  describe "OBDA.query forwards guard options" do
    test "require_authorizer: true refuses a resource without an authorizer" do
      assert {:error, %{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               OBDA.query([{Plain, title_mapping(Plain)}], @select, domain: Domain, require_authorizer: true)
    end

    test "without require_authorizer the same resource is readable" do
      assert {:ok, %OBDA.Result{bindings: [row]}} =
               OBDA.query([{Plain, title_mapping(Plain)}], @select, domain: Domain)

      assert to_string(row["s"]) == "urn:uuid:title-one"
    end

    test "require_tenant: true refuses a multitenant resource read without tenant" do
      assert {:error, %{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}} =
               OBDA.query([{Tenanted, title_mapping(Tenanted)}], @select, domain: Domain, require_tenant: true)
    end

    test "require_tenant: true admits the read when a tenant is given" do
      assert {:ok, %OBDA.Result{bindings: [row]}} =
               OBDA.query([{Tenanted, title_mapping(Tenanted)}], @select,
                 domain: Domain,
                 require_tenant: true,
                 tenant: "A"
               )

      assert to_string(row["s"]) == "urn:uuid:title-t1"
    end
  end
end
