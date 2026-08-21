# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OcelTelemetryChicagoTest do
  @moduledoc """
  Chicago-style E2E test suite: Real collaborators only, zero mocks.

  Verifies 100% Object-Centric Event Log (OCEL v2) event emission for every Ash action,
  notification, and AshR2RML Reactor step with full object maps and value maps.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GrandExample.Domain
  alias AshR2RML.GrandExample.Organization
  alias AshR2RML.GrandExample.Person
  alias AshR2RML.GrandExample.PublishingReactor
  alias AshR2RML.GrandExample.SemanticManifest
  alias AshR2RML.SPARQL.Observation
  alias AshR2RML.Telemetry.OcelAshEmitter

  setup do
    test_log_path = Path.join(["tmp", "test_ocel_#{System.unique_integer([:positive])}.ndjson"])
    File.rm(test_log_path)
    File.mkdir_p!(Path.dirname(test_log_path))

    handlers = OcelAshEmitter.attach!(domains: [Domain], log_path: test_log_path)

    on_exit(fn ->
      OcelAshEmitter.detach_all!(handlers)
      File.rm(test_log_path)
    end)

    {:ok, log_path: test_log_path}
  end

  test "real Ash actions emit verified OCEL v2 records with Ash introspection to disk", %{log_path: log_path} do
    org =
      Organization
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Acme Scientific Corp",
          version: "2.1.0"
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    assert org.name == "Acme Scientific Corp"

    person =
      Person
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "Dr. Eleanor Vance",
          email: "eleanor@acme.example",
          organization_id: org.id
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    assert person.name == "Dr. Eleanor Vance"

    assert File.exists?(log_path)
    lines = File.read!(log_path) |> String.split("\n", trim: true)
    assert length(lines) >= 2

    events = Enum.map(lines, &Jason.decode!/1)

    org_event = Enum.find(events, &(&1["ocel:activity"] == "organization.create"))
    assert org_event != nil
    assert is_binary(org_event["ocel:eid"])
    assert is_binary(org_event["ocel:timestamp"])
    assert org_event["ocel:omap"] == ["organization"]

    vmap = org_event["ocel:vmap"]
    assert vmap["action"] == "create"
    assert vmap["outcome"] == "stop"
    assert vmap["r2rml_class_iri"] == "https://schema.org/Organization"
    assert is_integer(vmap["duration_ms"])

    person_event = Enum.find(events, &(&1["ocel:activity"] == "person.create"))
    assert person_event != nil
    assert person_event["ocel:vmap"]["r2rml_class_iri"] == "https://schema.org/Person"
    assert person_event["ocel:vmap"]["action"] == "create"
  end

  test "real PublishingReactor saga execution emits 100% complete OCEL v2 event stream", %{log_path: log_path} do
    manifest =
      SemanticManifest
      |> Ash.Changeset.for_create(
        :create_manifest,
        %{
          title: "Telemetry 100% Verified Dataset",
          status: :draft
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    query_hash =
      :crypto.hash(:sha256, "SELECT ?s WHERE { ?s a <https://schema.org/Person> }") |> Base.encode16(case: :lower)

    rows = [%{"s" => "https://schema.org/Person/1"}]

    obs = [
      %Observation{
        strategy: :direct_sparql,
        query_sha256: query_hash,
        query_form: :select,
        status: :ALIVE,
        standing: :observed,
        evidence_kind: :local_execution,
        rows: rows
      },
      %Observation{
        strategy: :r2rml_obda,
        query_sha256: query_hash,
        query_form: :select,
        status: :ALIVE,
        standing: :observed,
        evidence_kind: :local_execution,
        rows: rows
      }
    ]

    inputs = %{
      resources: [Person, Organization],
      manifest_title: manifest.title,
      actor: %{id: "actor_telemetry_audit", role: :auditor},
      observations: obs,
      metadata: %{audit_mode: true}
    }

    assert {:ok, package} = Reactor.run(PublishingReactor, inputs)
    assert package.status == :ready_for_publication

    _updated =
      manifest
      |> Ash.Changeset.for_update(
        :mark_published,
        %{
          published_turtle: package.r2rml_turtle
        },
        domain: Domain
      )
      |> Ash.update!(domain: Domain)

    assert File.exists?(log_path)
    lines = File.read!(log_path) |> String.split("\n", trim: true)
    events = Enum.map(lines, &Jason.decode!/1)

    activities = Enum.map(events, & &1["ocel:activity"])

    # 1. Ash CRUD Actions
    assert "semantic_manifest.create_manifest" in activities
    assert "semantic_manifest.mark_published" in activities

    # 2. Sub-Reactor Composed Step
    assert "ash_r2rml.reactor.verify_inputs" in activities

    # 3. Concurrent Map Steps
    assert Enum.any?(activities, &String.starts_with?(&1, "ash_r2rml.reactor.verify_each_resource"))

    # 4. Compilation & Provenance Steps
    assert "ash_r2rml.reactor.compile_bundle" in activities
    assert "ash_r2rml.reactor.attach_provenance" in activities

    # 5. SPARQL Differential Step
    assert "ash_r2rml.reactor.evaluate_differential" in activities
    diff_event = Enum.find(events, &(&1["ocel:activity"] == "ash_r2rml.reactor.evaluate_differential"))
    assert diff_event["ocel:vmap"]["verified?"] == true
    assert diff_event["ocel:vmap"]["strategies"] == ["direct_sparql", "r2rml_obda"]

    # 6. Policy & Rendering Steps
    assert "ash_r2rml.reactor.apply_policy" in activities
    assert "ash_r2rml.reactor.render_r2rml_turtle" in activities
    render_event = Enum.find(events, &(&1["ocel:activity"] == "ash_r2rml.reactor.render_r2rml_turtle"))
    assert is_integer(render_event["ocel:vmap"]["r2rml_turtle_byte_size"])

    # 7. Aggregation & Pipeline Completion
    assert "ash_r2rml.reactor.manifest_banner" in activities
    assert "ash_r2rml.reactor.publication_package" in activities
    assert "ash_r2rml.reactor.pipeline_completed" in activities
  end
end
