# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OcelTelemetryChicagoTest do
  @moduledoc """
  Chicago-style telemetry tests with real Ash and Reactor collaborators.

  The boundary is fail-closed: an Ash action telemetry event may carry a real
  instance identity, but a resource module/type is never substituted when the
  action telemetry metadata does not expose that instance.
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

  test "real Ash actions never use resource types as fake OCEL object instances", %{log_path: log_path} do
    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Acme Scientific Corp", version: "2.1.0"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    person =
      Person
      |> Ash.Changeset.for_create(
        :create,
        %{name: "Dr. Eleanor Vance", email: "eleanor@acme.example", organization_id: org.id},
        domain: Domain
      )
      |> Ash.create!(domain: Domain)

    assert org.name == "Acme Scientific Corp"
    assert person.name == "Dr. Eleanor Vance"
    assert File.exists?(log_path)

    events =
      log_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    org_event = Enum.find(events, &(&1["ocel:activity"] == "organization.create"))
    assert org_event != nil
    assert is_binary(org_event["ocel:eid"])
    assert is_binary(org_event["ocel:timestamp"])
    assert is_list(org_event["ocel:omap"])
    assert is_list(org_event["ocel:e2o"])
    refute "organization" in org_event["ocel:omap"]

    assert Enum.sort(org_event["ocel:omap"]) ==
             org_event["ocel:e2o"] |> Enum.map(& &1["ocel:oid"]) |> Enum.uniq() |> Enum.sort()

    assert Enum.all?(org_event["ocel:omap"], fn object_id ->
             String.contains?(object_id, ":") or String.starts_with?(object_id, "urn:")
           end)

    vmap = org_event["ocel:vmap"]
    assert vmap["action"] == "create"
    assert vmap["outcome"] == "stop"
    assert vmap["r2rml_class_iri"] == "https://schema.org/Organization"
    assert is_integer(vmap["duration_ms"])

    person_event = Enum.find(events, &(&1["ocel:activity"] == "person.create"))
    assert person_event != nil
    assert person_event["ocel:vmap"]["r2rml_class_iri"] == "https://schema.org/Person"
    assert person_event["ocel:vmap"]["action"] == "create"
    refute "person" in person_event["ocel:omap"]
  end

  test "real PublishingReactor saga emits identity-bearing artifacts rather than type placeholders", %{log_path: log_path} do
    manifest =
      SemanticManifest
      |> Ash.Changeset.for_create(:create_manifest, %{title: "Telemetry Verified Dataset", status: :draft}, domain: Domain)
      |> Ash.create!(domain: Domain)

    query_hash =
      :crypto.hash(:sha256, "SELECT ?s WHERE { ?s a <https://schema.org/Person> }")
      |> Base.encode16(case: :lower)

    rows = [%{"s" => "https://schema.org/Person/1"}]

    observations = [
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
      observations: observations,
      metadata: %{audit_mode: true}
    }

    assert {:ok, package} = Reactor.run(PublishingReactor, inputs)
    assert package.status == :ready_for_publication

    _updated =
      manifest
      |> Ash.Changeset.for_update(:mark_published, %{published_turtle: package.r2rml_turtle}, domain: Domain)
      |> Ash.update!(domain: Domain)

    events =
      log_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    activities = Enum.map(events, & &1["ocel:activity"])
    assert "semantic_manifest.create_manifest" in activities
    assert "semantic_manifest.mark_published" in activities
    assert "ash_r2rml.reactor.verify_inputs" in activities
    assert Enum.any?(activities, &String.starts_with?(&1, "ash_r2rml.reactor.verify_each_resource"))
    assert "ash_r2rml.reactor.compile_bundle" in activities
    assert "ash_r2rml.reactor.attach_provenance" in activities
    assert "ash_r2rml.reactor.evaluate_differential" in activities
    assert "ash_r2rml.reactor.apply_policy" in activities
    assert "ash_r2rml.reactor.render_r2rml_turtle" in activities
    assert "ash_r2rml.reactor.manifest_banner" in activities
    assert "ash_r2rml.reactor.publication_package" in activities
    assert "ash_r2rml.reactor.pipeline_completed" in activities

    diff_event = Enum.find(events, &(&1["ocel:activity"] == "ash_r2rml.reactor.evaluate_differential"))
    assert diff_event["ocel:vmap"]["verified?"] == true
    assert diff_event["ocel:vmap"]["strategies"] == ["direct_sparql", "r2rml_obda"]
    assert Enum.all?(diff_event["ocel:omap"], &String.starts_with?(&1, "urn:"))

    render_event = Enum.find(events, &(&1["ocel:activity"] == "ash_r2rml.reactor.render_r2rml_turtle"))
    assert is_integer(render_event["ocel:vmap"]["r2rml_turtle_byte_size"])
    assert Enum.all?(render_event["ocel:omap"], &String.starts_with?(&1, "urn:sha256:"))
  end
end
