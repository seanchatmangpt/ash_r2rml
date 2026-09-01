# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.InMemoryTest do
  @moduledoc """
  Chicago-style: real `Ash.DataLayer.Ets` resource, real `Ash.create!`/`Ash.read!`, real
  `SPARQL.ex` execution via `AshR2RML.SPARQL.Local`. No mocked collaborator anywhere in
  this suite -- the one thing genuinely infeasible to run for real is Ontop itself (an
  external JDBC-backed process), which is exactly what this module exists to avoid needing.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.GrandExample.{Domain, Organization, Person}
  alias AshR2RML.OBDA.InMemory

  defmodule SensitiveDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshR2RML.OBDA.InMemoryTest.SensitiveEntity
    end
  end

  # A real Ash resource with a `sensitive?: true` attribute (Ash core's own redaction
  # flag, independent of any specific encryption library like ash_cloak) that is also
  # R2RML-mapped -- the real shape of the leak this fixture exercises: `Ash.read!/2`
  # returns the real plaintext `:api_token` value exactly like `:label`, so only
  # `InMemory`'s own `sensitive?` check (not Ash's read pipeline) stands between that
  # plaintext and the materialized RDF graph.
  defmodule SensitiveEntity do
    use Ash.Resource,
      domain: AshR2RML.OBDA.InMemoryTest.SensitiveDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML]

    r2rml do
      class_iri("https://example.org/ontology/SensitiveEntity")
      subject_template("https://example.org/sensitive/{id}")
      table_name("sensitive_entities")

      attribute_mappings([
        {:label, "https://schema.org/name"},
        {:api_token, "https://example.org/ontology/apiToken"}
      ])
    end

    actions do
      defaults [:read, :update, :destroy]

      create :create do
        primary? true
        accept [:label, :api_token]
      end
    end

    attributes do
      uuid_primary_key :id
      attribute :label, :string, allow_nil?: false, public?: true
      attribute :api_token, :string, allow_nil?: false, public?: true, sensitive?: true
    end
  end

  setup do
    {:ok, org_mapping} = AshR2RML.Resource.Info.mapping_result(Organization)
    {:ok, person_mapping} = AshR2RML.Resource.Info.mapping_result(Person)
    %{mapping: org_mapping, org_mapping: org_mapping, person_mapping: person_mapping}
  end

  test "materializes real ETS-backed rows into a real RDF.Graph", %{mapping: mapping} do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Acme", version: "1.0.0"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    assert {:ok, graph} = InMemory.materialize(Organization, mapping, domain: Domain)

    subject = RDF.iri("https://schema.org/Organization/#{org.id}")
    assert RDF.Graph.include?(graph, {subject, RDF.iri("https://schema.org/name"), RDF.literal("Acme")})

    assert RDF.Graph.include?(
             graph,
             {subject, RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
              RDF.iri("https://schema.org/Organization")}
           )
  end

  test "queries the materialized graph with real SPARQL via AshR2RML.SPARQL.Local", %{mapping: mapping} do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Beta Corp", version: "2.0.0"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    assert {:ok, observation} =
             InMemory.query(
               Organization,
               mapping,
               "SELECT ?s WHERE { ?s a <https://schema.org/Organization> }",
               domain: Domain
             )

    assert observation.status == :PARTIAL_ALIVE
    assert observation.metadata.engine == :in_memory_ets
    # `Ash.DataLayer.Ets` shares one global table across the test process, so other tests'
    # rows may also be present; assert real membership of this test's own row rather than
    # exact-set equality.
    assert %{"s" => "https://schema.org/Organization/#{org.id}"} in observation.rows
  end

  test "queries across multiple resources in one SPARQL query via a real Ash relationship join",
       %{org_mapping: org_mapping, person_mapping: person_mapping} do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Cross-Join Corp", version: "3.0.0"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    person =
      Person
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Ada Join", email: "ada.join@example.com", organization_id: org.id},
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    assert {:ok, observation} =
             InMemory.query_many(
               [{Organization, org_mapping}, {Person, person_mapping}],
               """
               SELECT ?person ?orgName WHERE {
                 ?person <https://schema.org/memberOf> ?org .
                 ?org <https://schema.org/name> ?orgName .
               }
               """,
               domain: Domain
             )

    assert observation.status == :PARTIAL_ALIVE
    assert observation.metadata.engine == :in_memory_ets

    assert %{"person" => "https://schema.org/Person/#{person.id}", "orgName" => "Cross-Join Corp"} in observation.rows
  end

  test "CONSTRUCT queries return real projected triples, not bindings", %{mapping: mapping} do
    Organization
    |> Ash.Changeset.for_create(:create, %{name: "Construct Co", version: "1.0.0"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    assert {:ok, observation} =
             InMemory.query(
               Organization,
               mapping,
               "CONSTRUCT { ?s <http://example.org/label> ?name } WHERE { ?s <https://schema.org/name> ?name }",
               domain: Domain
             )

    assert observation.query_form == :construct
    assert observation.result_kind == :rdf

    assert %{"predicate" => "http://example.org/label", "object" => "Construct Co"} =
             Enum.find(observation.rows, &(&1["object"] == "Construct Co"))
  end

  test "field policies enforced by real Ash actors carry through into the RDF projection" do
    alias AshR2RML.Fortune5.{Domain, PaymentGateway}

    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(PaymentGateway)

    gateway =
      PaymentGateway
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Field Policy Gateway",
          provider: "stripe",
          api_endpoint: "https://api.stripe.com",
          secret_key: "sk_live_TOPSECRET"
        },
        domain: Domain,
        actor: %{role: :admin}
      )
      |> Ash.create!(domain: Domain, actor: %{role: :admin})

    subject = RDF.iri("https://finance.fortune5.com/gateways/#{gateway.id}")
    secret_predicate = RDF.iri("https://w3id.org/fortune5/ontology#apiKeySecret")

    has_secret_triple? = fn graph ->
      Enum.any?(RDF.Graph.triples(graph), fn {_s, p, _o} -> p == secret_predicate end)
    end

    assert {:ok, admin_graph} = InMemory.materialize(PaymentGateway, mapping, domain: Domain, actor: %{role: :admin})

    assert RDF.Graph.include?(admin_graph, {
             subject,
             RDF.iri("https://schema.org/name"),
             RDF.literal("Field Policy Gateway")
           })

    assert has_secret_triple?.(admin_graph)

    # A non-admin actor is real Ash-denied `:secret_key` via `field_policy [:secret_key]`
    # (`test/support/fortune5/ash_factory.ex`). Ash returns `%Ash.ForbiddenField{}`, not
    # `nil`, for that attribute -- materialization must omit the triple rather than crash
    # trying to stringify the sentinel, and must never leak the secret to this actor.
    assert {:ok, guest_graph} = InMemory.materialize(PaymentGateway, mapping, domain: Domain, actor: %{role: :guest})

    assert RDF.Graph.include?(guest_graph, {
             subject,
             RDF.iri("https://schema.org/name"),
             RDF.literal("Field Policy Gateway")
           })

    refute has_secret_triple?.(guest_graph)
  end

  test "adversarial: a :template-substituted value crafted to break IRIREF syntax is percent-encoded, not embedded or dropped",
       %{org_mapping: org_mapping} do
    # This matches Ontop's own confirmed behavior against a live Postgres+Ontop stack:
    # Ontop's `rr:template` substitution percent-encodes the substituted value (`>` -> `%3E`,
    # space -> `%20`, `:`/`/` -> `%3A`/`%2F`) rather than rejecting the row. The default
    # `subject_template` is `:template` strategy (`"https://schema.org/Organization/{id}"`),
    # so exercise the attack through the `:id` field directly via a synthetic mapping whose
    # template substitutes a plain string instead of a generated UUID.
    template_mapping = %{
      org_mapping
      | subject_map: %{org_mapping.subject_map | strategy: :template, value: "https://example.org/adv/{name}"}
    }

    injected_name = "evil> . <http://evil.example/injected> <http://evil.example/p> <http://evil.example/o"

    Organization
    |> Ash.Changeset.for_create(:create, %{name: injected_name, version: "1.0.0"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    assert {:ok, graph} = InMemory.materialize(Organization, template_mapping, domain: Domain)

    # The row is preserved (unlike the :column case below) with the dangerous characters
    # percent-encoded, exactly as Ontop projects the same input.
    expected_subject =
      RDF.iri(
        "https://example.org/adv/" <>
          "evil%3E%20.%20%3Chttp%3A%2F%2Fevil.example%2Finjected%3E%20%3Chttp%3A%2F%2Fevil.example%2Fp%3E%20%3Chttp%3A%2F%2Fevil.example%2Fo"
      )

    assert Enum.any?(RDF.Graph.subjects(graph), &(&1 == expected_subject))

    # No real triple was spliced in with the attacker-chosen subject/predicate -- the raw
    # injected text only ever exists as a percent-encoded, inert part of the one legitimate
    # subject IRI (and, separately, as a correctly-escaped `:name` literal value, which is
    # not an injection surface: RDF.ex's literal serialization already handles that safely).
    injected_subject_or_predicate? = fn {s, p, _o} ->
      to_string(s) == "http://evil.example/injected" or to_string(p) == "http://evil.example/p"
    end

    refute Enum.any?(RDF.Graph.triples(graph), injected_subject_or_predicate?)
    assert to_string(expected_subject) =~ "%3E"
  end

  test "detects field-policy-protected R2RML-mapped attributes against a real resource" do
    # `AshR2RML.Security.sanitize_mapping/2` closes the confirmed gap structurally: Ontop
    # connects directly to Postgres over JDBC with no Ash actor context, so a field_policy is
    # unenforceable once its attribute is R2RML-mapped and the resource is deployed via that
    # path -- so on an AshPostgres.DataLayer-backed resource, that attribute's
    # predicate_object_map is removed before rendering, not merely refused-and-explained.
    #
    # PaymentGateway's real `field_policies` block (test/support/fortune5/ash_factory.ex)
    # declares an explicit policy on :secret_key (`actor_attribute_equals(:role, :admin)`) and
    # on :name/:provider/:api_endpoint/:criticality/:status/:cloud_region_id (`always()`);
    # :id carries no field_policy at all. `unenforceable_attributes/2` is exercised directly
    # against these real policies -- it does not distinguish "always grants" from
    # "conditionally grants" (deliberately conservative, see moduledoc), so every R2RML-mapped
    # attribute under an explicit field_policy is flagged, and :id (no policy at all) is not.
    alias AshR2RML.Fortune5.PaymentGateway
    alias AshR2RML.Security

    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(PaymentGateway)
    flagged = Security.unenforceable_attributes(PaymentGateway, mapping)

    assert :secret_key in flagged
    assert :name in flagged
    refute :id in flagged

    # PaymentGateway is Ash.DataLayer.Ets-backed in this test suite, so sanitize_mapping/2 is a
    # no-op regardless -- the vulnerable path is specifically AshPostgres.DataLayer, confirmed
    # live against Ontop. This proves the guard does not false-positive on the safe backend.
    assert AshR2RML.DataLayer.backend(PaymentGateway) == :ets
    assert Security.sanitize_mapping(PaymentGateway, mapping) == mapping
  end

  test "removes field-policy-protected attributes from the real mapping, recording the exclusion" do
    # Exercises the actual structural fix (Security.remove_attributes/2) directly against
    # PaymentGateway's real predicate_object_maps -- decoupled from the AshPostgres.DataLayer
    # backend gate (which this test env cannot exercise end-to-end: ash_postgres is not a
    # dependency of this project). This is what sanitize_mapping/2 would apply automatically
    # were PaymentGateway AshPostgres.DataLayer-backed instead of Ets-backed.
    alias AshR2RML.Fortune5.PaymentGateway
    alias AshR2RML.Security

    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(PaymentGateway)
    sanitized = Security.remove_attributes(mapping, [:secret_key])

    refute Enum.any?(sanitized.predicate_object_maps, &(&1.attribute == :secret_key))
    assert Enum.any?(mapping.predicate_object_maps, &(&1.attribute == :secret_key))
    assert length(sanitized.predicate_object_maps) == length(mapping.predicate_object_maps) - 1
    assert sanitized.metadata[:field_policy_excluded_attributes] == [:secret_key]

    # Every other real attribute mapping survives untouched.
    assert Enum.any?(sanitized.predicate_object_maps, &(&1.attribute == :name))

    # [] is a real, tested no-op -- confirms sanitize_mapping/2's :ets no-op path above isn't
    # accidentally passing because remove_attributes/2 always no-ops.
    assert Security.remove_attributes(mapping, []) == mapping
  end

  test "adversarial: a subject value crafted to break IRIREF syntax is excluded, not embedded",
       %{org_mapping: org_mapping} do
    # `RDF.iri/1` does not validate RFC 3987 syntax, and RDF.ex's Turtle writer does not
    # escape a raw `>` inside an IRIREF -- so if an attacker-controlled attribute value were
    # substituted into a subject/object IRI unvalidated, the extra text would splice
    # arbitrary triples into any Turtle serialization of the graph. Exercise this via a
    # `:column` subject-map strategy over a plain writable string attribute (`:name`) -- the
    # realistic shape of the risk for any resource whose identity isn't a generated UUID.
    malicious_mapping = %{org_mapping | subject_map: %{org_mapping.subject_map | strategy: :column, value: :name}}

    injected_name =
      "https://schema.org/Organization/1> . <http://evil.example/injected> <http://evil.example/p> <http://evil.example/o"

    Organization
    |> Ash.Changeset.for_create(:create, %{name: injected_name, version: "9.9.9"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    assert {:ok, graph} = InMemory.materialize(Organization, malicious_mapping, domain: Domain)

    # The row is excluded entirely (fail closed) rather than embedding a malformed IRI.
    refute Enum.any?(RDF.Graph.subjects(graph), fn subject -> String.contains?(to_string(subject), "evil.example") end)

    turtle = RDF.Turtle.write_string!(graph)
    refute turtle =~ "evil.example"
  end

  test "resolves a composite-key (2-column) rr:joinCondition relationship into a real object IRI" do
    # R2RML-107 AC1/AC2: `Shipment` carries both halves (`:region`, `:warehouse_code`) of a
    # composite foreign key into `Warehouse`'s real `{region, code}` natural key. The R2RML
    # DSL's `relationship_mappings` only introspects single-column Ash `belongs_to`
    # `source_attribute`/`destination_attribute` pairs, so this genuine multi-column join is
    # constructed by hand against each resource's real mapping -- exactly the way the existing
    # "refuses unsupported subject-map strategies" test below hand-builds a mapping -- while
    # every row is still real: real `Ash.DataLayer.Ets`-backed resources, real `Ash.create!`,
    # real `Ash.read!` inside `InMemory.materialize_many/2`.
    #
    # `Warehouse`'s mapping is hand-built rather than DSL-derived: its whole point is a
    # semantic identity keyed on `{region, code}`, not the physical `:id` primary key that
    # `AshR2RML.VerifyMapping`'s `primary_key_in_template` check requires of every DSL-declared
    # `r2rml` subject_template (see `Warehouse`'s moduledoc for the full rationale).
    alias AshR2RML.GrandExample.{Shipment, Warehouse}
    alias AshR2RML.Mapping.{JoinCondition, LogicalTable, ReferenceObjectMap, SubjectMap}

    warehouse_mapping = %AshR2RML.Mapping.Resource{
      ash_resource: Warehouse,
      logical_table: %LogicalTable{table_name: "schema_warehouses"},
      subject_map: %SubjectMap{strategy: :template, value: "https://schema.org/Warehouse/{region}/{code}"},
      class_iris: ["https://schema.org/Warehouse"]
    }

    {:ok, shipment_mapping} = AshR2RML.Resource.Info.mapping_result(Shipment)

    Warehouse
    |> Ash.Changeset.for_create(:create, %{region: "us-east", code: "W12", name: "East Hub"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    shipment =
      Shipment
      |> Ash.Changeset.for_create(
        :create,
        %{tracking_number: "TRK-1", region: "us-east", warehouse_code: "W12"},
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    composite_reference = %ReferenceObjectMap{
      relationship: :warehouse,
      predicate_iri: "https://schema.org/shippedFrom",
      parent_resource: Warehouse,
      joins: [
        %JoinCondition{child: "region", parent: "region"},
        %JoinCondition{child: "warehouse_code", parent: "code"}
      ]
    }

    shipment_mapping_with_join = %{shipment_mapping | reference_object_maps: [composite_reference]}

    assert {:ok, graph} =
             InMemory.materialize_many(
               [{Shipment, shipment_mapping_with_join}, {Warehouse, warehouse_mapping}],
               domain: Domain
             )

    shipment_subject = RDF.iri("https://schema.org/Shipment/#{shipment.id}")
    warehouse_object = RDF.iri("https://schema.org/Warehouse/us-east/W12")

    assert RDF.Graph.include?(
             graph,
             {shipment_subject, RDF.iri("https://schema.org/shippedFrom"), warehouse_object}
           )

    assert RDF.Graph.include?(
             graph,
             {warehouse_object, RDF.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
              RDF.iri("https://schema.org/Warehouse")}
           )
  end

  test ":join_table many-to-many reference object maps are refused with a typed refusal, not silently skipped",
       %{org_mapping: org_mapping} do
    # R2RML-107 AC3: the `joins: []` shape `AshR2RML.SemanticAdapter.convert_references/2`
    # emits for a `:join_table` many-to-many relationship is no longer a silent, unlabeled
    # omission -- it is now a real, typed `Refusal` propagated out of `materialize_many/2`.
    alias AshR2RML.Mapping.ReferenceObjectMap

    join_table_reference = %ReferenceObjectMap{
      relationship: :tags,
      predicate_iri: "https://schema.org/keywords",
      parent_resource: Organization,
      joins: [],
      metadata: %{kind: :many_to_many}
    }

    mapping_with_join_table = %{org_mapping | reference_object_maps: [join_table_reference]}

    Organization
    |> Ash.Changeset.for_create(:create, %{name: "Join Table Co", version: "1.0.0"}, domain: Domain)
    |> Ash.create!(domain: Domain)

    assert {:error, refusal} =
             InMemory.materialize_many([{Organization, mapping_with_join_table}], domain: Domain)

    assert refusal.code == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
    assert refusal.evidence.relationship == :tags
  end

  test "refuses unsupported subject-map strategies with a typed refusal instead of guessing" do
    unsupported_mapping = %AshR2RML.Mapping.Resource{
      ash_resource: Organization,
      logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "schema_organizations"},
      subject_map: %AshR2RML.Mapping.SubjectMap{strategy: :constant, value: "https://schema.org/one"}
    }

    assert {:error, refusal} = InMemory.materialize(Organization, unsupported_mapping, domain: Domain)
    assert refusal.code == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
  end

  test "refuses to materialize a sensitive?: true attribute by default, with a typed refusal" do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(SensitiveEntity)

    SensitiveEntity
    |> Ash.Changeset.for_create(:create, %{label: "Widget", api_token: "sk_live_TOPSECRET"}, domain: SensitiveDomain)
    |> Ash.create!(domain: SensitiveDomain)

    assert {:error, refusal} = InMemory.materialize(SensitiveEntity, mapping, domain: SensitiveDomain)

    assert refusal.code == :REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION
    assert refusal.evidence.attribute == :api_token
    assert refusal.subject == SensitiveEntity
  end

  test "materializes a sensitive?: true attribute's real value only with explicit allow_sensitive: true" do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(SensitiveEntity)

    entity =
      SensitiveEntity
      |> Ash.Changeset.for_create(:create, %{label: "Gadget", api_token: "sk_live_OPTEDIN"}, domain: SensitiveDomain)
      |> Ash.create!(domain: SensitiveDomain)

    assert {:ok, graph} =
             InMemory.materialize(SensitiveEntity, mapping, domain: SensitiveDomain, allow_sensitive: true)

    subject = RDF.iri("https://example.org/sensitive/#{entity.id}")

    assert RDF.Graph.include?(graph, {subject, RDF.iri("https://schema.org/name"), RDF.literal("Gadget")})

    assert RDF.Graph.include?(
             graph,
             {subject, RDF.iri("https://example.org/ontology/apiToken"), RDF.literal("sk_live_OPTEDIN")}
           )
  end
end
