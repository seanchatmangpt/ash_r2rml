# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ReactorEvidenceReplayTest do
  use ExUnit.Case, async: false

  alias AshR2RML.Evidence
  alias AshR2RML.GrandExample.{Organization, Person, PublishingReactor}
  alias AshR2RML.SPARQL.Observation
  alias AshR2RML.Telemetry.{OCEL2, OcelAshEmitter}

  setup do
    log_path = Path.join(["tmp", "reactor-evidence-replay-#{System.unique_integer([:positive])}.ndjson"])
    File.rm(log_path)
    File.mkdir_p!(Path.dirname(log_path))
    handlers = OcelAshEmitter.attach!(domains: [], log_path: log_path)

    on_exit(fn ->
      OcelAshEmitter.detach_all!(handlers)
      File.rm(log_path)
    end)

    {:ok, log_path: log_path}
  end

  test "two independent real Reactor runs converge on one semantic OCEL trace identity", %{log_path: log_path} do
    inputs = %{
      resources: [Person, Organization],
      manifest_title: "Replayable Mapping",
      actor: nil,
      observations: observations(),
      metadata: %{subject: :replayable_mapping}
    }

    assert {:ok, first_package} = Reactor.run(PublishingReactor, inputs)
    assert {:ok, second_package} = Reactor.run(PublishingReactor, inputs)
    assert first_package == second_package

    events = read_events(log_path)
    assert {:ok, %{valid?: true}} = OCEL2.validate(events)

    execution_ids =
      events
      |> Enum.map(&get_in(&1, ["ocel:vmap", "execution_id"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    assert length(execution_ids) == 2
    [first_execution, second_execution] = execution_ids
    refute first_execution == second_execution

    assert {:ok, first_trace} = Evidence.ocel_trace_id(events, first_execution)
    assert {:ok, second_trace} = Evidence.ocel_trace_id(events, second_execution)
    assert first_trace == second_trace

    for execution_id <- execution_ids do
      run_events = Enum.filter(events, &(get_in(&1, ["ocel:vmap", "execution_id"]) == execution_id))
      assert Enum.any?(run_events, &(&1["ocel:activity"] == "ash_r2rml.reactor.compile_bundle"))
      assert Enum.any?(run_events, &(&1["ocel:activity"] == "ash_r2rml.reactor.render_r2rml_turtle"))
      assert Enum.any?(run_events, &(&1["ocel:activity"] == "ash_r2rml.reactor.pipeline_completed"))

      assert Enum.all?(run_events, fn event ->
               is_binary(event["ocel:vmap"]["result_evidence_id"])
             end)
    end
  end

  defp observations do
    query = "SELECT ?s WHERE { ?s a <https://schema.org/Person> }"
    query_sha256 = Evidence.sha256(query)
    rows = [%{"s" => "https://schema.org/Person/1"}]
    result_sha256 = AshR2RML.SPARQL.Result.hash_rows(rows)

    [
      %Observation{
        strategy: :local_rdf,
        query_sha256: query_sha256,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed_local_rdf_execution,
        evidence_kind: :in_memory_execution,
        result_kind: :bindings,
        result_sha256: result_sha256,
        rows: rows,
        metadata: %{engine: :sparql_ex}
      },
      %Observation{
        strategy: :protocol,
        query_sha256: query_sha256,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed_remote_query,
        evidence_kind: :sparql_protocol,
        endpoint: "https://example.invalid/sparql",
        result_kind: :bindings,
        result_sha256: result_sha256,
        rows: rows,
        metadata: %{client: :sparql_client}
      }
    ]
  end

  defp read_events(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end
end
