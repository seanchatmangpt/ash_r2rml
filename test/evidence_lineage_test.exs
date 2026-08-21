# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.EvidenceLineageTest do
  use ExUnit.Case, async: false

  alias AshR2RML.Evidence
  alias AshR2RML.Reactor.Middleware.TelemetryLogger
  alias AshR2RML.SPARQL.{Differential, Observation}
  alias AshR2RML.Telemetry.{OCEL2, OcelAshEmitter}

  test "observation evidence identity is content-addressed rather than instance-addressed" do
    rows = [%{"person" => "https://example.org/bob"}]
    query_sha256 = Evidence.sha256("SELECT ?person WHERE { ?s ?p ?person }")

    left = %Observation{
      strategy: :local_rdf,
      query_sha256: query_sha256,
      query_form: :select,
      status: :PARTIAL_ALIVE,
      standing: :observed_local_rdf_execution,
      evidence_kind: :in_memory_execution,
      result_kind: :bindings,
      result_sha256: AshR2RML.SPARQL.Result.hash_rows(rows),
      rows: rows,
      metadata: %{engine: :sparql_ex}
    }

    replay = %{left | rows: Enum.reverse(rows)}

    assert Evidence.id(left) == Evidence.id(replay)
    assert Evidence.id(left) == Evidence.id(left)
  end

  test "differential receipt binds the observations, not only equal row values" do
    rows = [%{"person" => "https://example.org/bob"}]
    query_sha256 = Evidence.sha256("SELECT ?person WHERE { ?s ?p ?person }")

    local = observation(:local_rdf, :in_memory_execution, :observed_local_rdf_execution, query_sha256, rows)
    protocol = observation(:protocol, :sparql_protocol, :observed_remote_query, query_sha256, rows)

    assert {:ok, receipt} = Differential.compare(:person_query, [protocol, local])
    assert receipt.verified?
    assert receipt.evidence_id_by_strategy.local_rdf == Evidence.id(local)
    assert receipt.evidence_id_by_strategy.protocol == Evidence.id(protocol)
    assert :ok = Differential.require_observed(receipt)

    injected = %{protocol | evidence_kind: :injected_client, standing: :test_double_only}
    assert {:ok, synthetic_receipt} = Differential.compare(:person_query, [local, injected])
    assert synthetic_receipt.verified?

    assert {:error, refusal} = Differential.require_observed(synthetic_receipt)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
  end

  test "Reactor middleware and OCEL emitter preserve one execution id across step and pipeline evidence" do
    log_path = Path.join(["tmp", "evidence-lineage-#{System.unique_integer([:positive])}.ndjson"])
    File.rm(log_path)
    File.mkdir_p!(Path.dirname(log_path))

    handlers = OcelAshEmitter.attach!(domains: [], log_path: log_path)

    on_exit(fn ->
      OcelAshEmitter.detach_all!(handlers)
      File.rm(log_path)
    end)

    assert {:ok, context} = TelemetryLogger.init(%{})
    execution_id = Evidence.execution_id(context)
    assert is_binary(execution_id)

    step = %{name: :compile_resources}
    assert {:ok, step_context} = TelemetryLogger.event({:run_start, %{}}, step, context)

    bundle = %AshR2RML.Mapping.Bundle{resources: []}
    assert :ok = TelemetryLogger.event({:run_complete, bundle}, step, step_context)
    assert {:ok, ^bundle} = TelemetryLogger.complete(bundle, context)

    events =
      log_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert length(events) == 2
    assert {:ok, %{valid?: true, event_count: 2}} = OCEL2.validate(events)

    assert Enum.all?(events, fn event ->
             event["ocel:vmap"]["execution_id"] == execution_id
           end)

    step_event = Enum.find(events, &(&1["ocel:activity"] == "ash_r2rml.reactor.compile_resources"))
    assert step_event["ocel:vmap"]["mapping_sha256"] == Evidence.id(bundle)
    assert step_event["ocel:vmap"]["result_evidence_id"] == Evidence.id(bundle)
    assert "reactor-run:#{execution_id}" in step_event["ocel:omap"]

    assert {:ok, trace_id} = Evidence.ocel_trace_id(events, execution_id)
    assert is_binary(trace_id)
  end

  test "checked-in Livebook executes as a headless project-bound specification" do
    path = "documentation/how_to/replayable_semantic_evidence.livemd"

    assert {:ok, %{cells: 2, results: results}} =
             Mix.Tasks.AshR2rml.TestLivebooks.run_file(path)

    assert length(results) == 2
  end

  defp observation(strategy, evidence_kind, standing, query_sha256, rows) do
    %Observation{
      strategy: strategy,
      query_sha256: query_sha256,
      query_form: :select,
      status: :PARTIAL_ALIVE,
      standing: standing,
      evidence_kind: evidence_kind,
      result_kind: :bindings,
      result_sha256: AshR2RML.SPARQL.Result.hash_rows(rows),
      rows: rows,
      metadata: %{}
    }
  end
end
