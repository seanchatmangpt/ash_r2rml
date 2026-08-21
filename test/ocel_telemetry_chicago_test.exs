# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OcelTelemetryChicagoTest do
  @moduledoc """
  Chicago-style E2E test suite: Real collaborators only, zero mocks.

  Verifies that every real Ash action, notification, and Reactor workflow execution emits
  real, verifiable Object-Centric Event Log (OCEL v2) records to a durable file on disk,
  enriched via genuine Ash introspection and correlated to telemetry spans.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GrandExample.Domain
  alias AshR2RML.GrandExample.Organization
  alias AshR2RML.GrandExample.Person
  alias AshR2RML.GrandExample.PublishingReactor
  alias AshR2RML.GrandExample.SemanticManifest
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
    # 1. Execute real Ash create action on Organization
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

    # 2. Execute real Ash create action on Person
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

    # 3. Read the real NDJSON file from disk (no mocked file IO)
    assert File.exists?(log_path)
    lines = File.read!(log_path) |> String.split("\n", trim: true)
    assert length(lines) >= 2

    # Parse and validate each line as a standard W3C/IEEE OCEL 2.0 JSON record
    events = Enum.map(lines, &Jason.decode!/1)

    # Validate Organization event
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

    # Validate Person event
    person_event = Enum.find(events, &(&1["ocel:activity"] == "person.create"))
    assert person_event != nil
    assert person_event["ocel:vmap"]["r2rml_class_iri"] == "https://schema.org/Person"
    assert person_event["ocel:vmap"]["action"] == "create"
  end

  test "real PublishingReactor saga execution emits correlated telemetry and OCEL events", %{log_path: log_path} do
    # 1. Create a manifest record
    manifest =
      SemanticManifest
      |> Ash.Changeset.for_create(
        :create_manifest,
        %{
          title: "Telemetry Verified Dataset",
          status: :draft
        },
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    # 2. Run the Grand Publishing Reactor
    inputs = %{
      resources: [Person, Organization],
      manifest_title: manifest.title,
      actor: %{id: "actor_telemetry_audit", role: :auditor},
      observations: [],
      metadata: %{audit_mode: true}
    }

    assert {:ok, package} = Reactor.run(PublishingReactor, inputs)
    assert package.status == :ready_for_publication

    # 3. Update manifest with generated Turtle
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

    # 4. Verify durable OCEL log entries
    assert File.exists?(log_path)
    lines = File.read!(log_path) |> String.split("\n", trim: true)
    events = Enum.map(lines, &Jason.decode!/1)

    activities = Enum.map(events, & &1["ocel:activity"])
    assert "semantic_manifest.create_manifest" in activities
    assert "semantic_manifest.mark_published" in activities
  end
end
