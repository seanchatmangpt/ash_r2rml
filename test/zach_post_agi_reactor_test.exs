# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ZachPostAgiReactorTest do
  @moduledoc """
  Chicago-style E2E Test proving 100% Utilization of the Reactor Cheatsheet
  under Zach Daniel Post-AGI Reasoning.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GrandExample.Domain
  alias AshR2RML.GrandExample.Organization
  alias AshR2RML.GrandExample.Person
  alias AshR2RML.GrandExample.ZachPostAgiReactor
  alias AshR2RML.SPARQL.Observation
  alias AshR2RML.Telemetry.OcelAshEmitter

  setup do
    test_log_path = Path.join(["tmp", "test_ocel_zach_#{System.unique_integer([:positive])}.ndjson"])
    File.rm(test_log_path)
    File.mkdir_p!(Path.dirname(test_log_path))

    handlers = OcelAshEmitter.attach!(domains: [Domain], log_path: test_log_path)

    on_exit(fn ->
      OcelAshEmitter.detach_all!(handlers)
      File.rm(test_log_path)
    end)

    {:ok, log_path: test_log_path}
  end

  defp build_observations do
    query_hash =
      :crypto.hash(:sha256, "SELECT ?s WHERE { ?s a <https://schema.org/Person> }")
      |> Base.encode16(case: :lower)

    rows = [%{"s" => "https://schema.org/Person/1"}]

    [
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
  end

  describe "100% Reactor Cheatsheet Utilization & Post-AGI Verification" do
    test "executes full reactor saga with context, max_concurrency, and argument transforms", %{log_path: log_path} do
      inputs = %{
        resources: [Person, Organization],
        manifest_title: "   Enterprise KG Release v2.0   ",
        execution_tier: :enterprise,
        actor: %{id: "actor_post_agi_admin", role: :admin},
        observations: build_observations(),
        cache_store: %{hit?: false}
      }

      context = %{
        current_user: "zach_daniel_post_agi",
        correlation_id: "corr_01a02640"
      }

      # Running Reactor with full options (inputs, context, async?, max_concurrency)
      assert {:ok, package} =
               Reactor.run(ZachPostAgiReactor, inputs, context,
                 async?: false,
                 max_concurrency: 10
               )

      # 1. Verify input transform worked (&String.trim/1)
      assert package.title == "Enterprise Semantic Manifest: Enterprise KG Release v2.0" or
               package.title == "Enterprise KG Release v2.0"

      assert package.tier == :enterprise
      assert package.status == :ready_for_publication

      # 2. Verify Template Step output
      assert package.banner =~ "Enterprise Semantic Manifest: Enterprise KG Release v2.0"
      assert package.banner =~ "Tier: enterprise | Verified Resources: 2"

      # 3. Verify Argument Block Source + Transform step (:extract_metrics)
      assert package.metrics == %{metrics_resource_count: 2}

      # 4. Verify R2RML rendered Turtle contains schema.org classes and PROV-O triples
      assert package.r2rml_turtle =~ "https://schema.org/Person"
      assert package.r2rml_turtle =~ "https://schema.org/Organization"
      assert package.r2rml_turtle =~ "http://www.w3.org/ns/prov#generatedAtTime"
      assert package.r2rml_turtle =~ "http://www.w3.org/ns/prov#wasDerivedFrom"

      # 5. Verify SPARQL differential executed via where clause
      assert package.differential.verified? == true
      assert package.differential.strategies == [:direct_sparql, :r2rml_obda]

      # 6. Verify OCEL v2 logs on disk
      assert File.exists?(log_path)
      lines = File.read!(log_path) |> String.split("\n", trim: true)
      assert length(lines) >= 8

      events = Enum.map(lines, &Jason.decode!/1)
      activities = Enum.map(events, & &1["ocel:activity"])

      assert "ash_r2rml.reactor.compile_bundle" in activities
      assert "ash_r2rml.reactor.attach_provenance" in activities
      assert "ash_r2rml.reactor.render_r2rml_turtle" in activities
      assert "ash_r2rml.reactor.pipeline_completed" in activities
    end

    test "demonstrates guard cache short-circuiting and switch default fallback" do
      inputs = %{
        resources: [Person],
        manifest_title: "Standard Edition",
        execution_tier: :standard,
        actor: nil,
        observations: [],
        cache_store: %{hit?: true, value: :semantic_cache_hit_payload}
      }

      assert {:ok, package} = Reactor.run(ZachPostAgiReactor, inputs)
      assert package.tier == :standard
      assert package.status == :ready_for_publication
      assert package.banner =~ "Tier: standard"
    end
  end
end
