# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.DfCMTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.{DfCM, Observability, Release, Replay, Resilience, Security}

  test "the design graph preserves a broad reversible possibility space" do
    graph = DfCM.default_graph()

    assert length(graph.dimensions) == 20
    assert length(graph.constraints) >= 20
    assert graph.metadata.do_path == :brce
    assert graph.metadata.generated_projection_authority == :ggen
    assert String.length(DfCM.graph_sha256(graph)) == 64

    assert Enum.all?(graph.dimensions, fn dimension ->
             dimension.options != [] and dimension.default in dimension.options
           end)
  end

  test "default assignment is admitted and deterministic" do
    graph = DfCM.default_graph()
    assignment = default_assignment(graph)

    first = DfCM.evaluate(graph, assignment)
    second = DfCM.evaluate(graph, assignment)

    assert first.id == second.id
    assert first.assignment == second.assignment
    assert first.refusals == []
    assert first.status == :ADMITTED
    assert first.standing == :candidate_constructible
    assert first.required_evidence != []
  end

  test "active-active without strong consistency or receipted writes is refused" do
    graph = DfCM.default_graph()

    candidate =
      graph
      |> default_assignment()
      |> Map.merge(%{
        deployment_topology: :multi_region_active_active,
        consistency_model: :eventual,
        execution_mode: :read_only_runtime,
        control_plane: :regional_federated
      })
      |> then(&DfCM.evaluate(graph, &1))

    assert candidate.status == :REFUSED
    assert Enum.any?(candidate.refusals, &(&1.rule == :active_active_requires_strong_or_idempotent))
  end

  test "air gap requires offline artifact distribution and no external protocol" do
    graph = DfCM.default_graph()

    candidate =
      graph
      |> default_assignment()
      |> Map.merge(%{
        network_boundary: :air_gapped,
        artifact_distribution: :replicated_registry,
        obda_topology: :external_protocol
      })
      |> then(&DfCM.evaluate(graph, &1))

    rules = Enum.map(candidate.refusals, & &1.rule)
    assert :air_gap_requires_offline_distribution in rules
    assert :air_gap_forbids_external_protocol in rules
  end

  test "regulated topology rejects known isolation gaps" do
    graph = DfCM.default_graph()

    pci =
      graph
      |> default_assignment()
      |> Map.merge(%{compliance_profile: :pci, runtime_isolation: :shared_pool})
      |> then(&DfCM.evaluate(graph, &1))

    hipaa =
      graph
      |> default_assignment()
      |> Map.merge(%{compliance_profile: :hipaa, data_residency: :unrestricted})
      |> then(&DfCM.evaluate(graph, &1))

    assert Enum.any?(pci.refusals, &(&1.rule == :pci_forbids_shared_pool))
    assert Enum.any?(hipaa.refusals, &(&1.rule == :hipaa_forbids_unrestricted_residency))
  end

  test "bounded enumeration can select a complete exact assignment" do
    graph = DfCM.default_graph()
    assignment = default_assignment(graph)

    assert {:ok, [candidate], receipt} =
             DfCM.enumerate(graph,
               select: assignment,
               max_candidates: 10,
               max_examined: 10
             )

    assert candidate.assignment == assignment
    assert receipt.returned == 1
    assert receipt.graph_sha256 == DfCM.graph_sha256(graph)
    assert String.length(receipt.receipt_sha256) == 64
  end

  test "frontier preserves candidates instead of manufacturing one ambient winner" do
    graph = DfCM.default_graph()
    base = default_assignment(graph)

    candidates =
      for release <- [:rolling, :blue_green, :canary],
          isolation <- [:tenant_pool, :cell_pool, :dedicated_workload] do
        base
        |> Map.put(:release_strategy, release)
        |> Map.put(:runtime_isolation, isolation)
        |> then(&DfCM.evaluate(graph, &1))
      end

    frontier = DfCM.frontier(candidates, 8)

    assert frontier != []
    assert length(frontier) <= 8
    assert Enum.all?(frontier, &(&1.refusals == []))
    assert length(Enum.uniq(Enum.map(frontier, & &1.id))) == length(frontier)
  end

  test "candidate selection requires explicit authority receipt" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, default_assignment(graph))

    assert {:error, refusal} = DfCM.select(candidate, %{authorized?: false})
    assert refusal.code == :REFUSED_DFCM_SELECTION_WITHOUT_AUTHORITY

    authority = %{authorized?: true, receipt_sha256: String.duplicate("a", 64)}
    assert {:ok, selected} = DfCM.select(candidate, authority)
    assert selected.selected?
    assert selected.standing == :selected_for_construct
  end

  test "receipted write candidate exposes irreversible edges and BRCE evidence" do
    graph = DfCM.default_graph()

    candidate =
      graph
      |> default_assignment()
      |> Map.merge(%{
        execution_mode: :receipted_write_runtime,
        observability: :open_telemetry_receipts,
        migration_strategy: :shadow_dual_write
      })
      |> then(&DfCM.evaluate(graph, &1))

    assert candidate.refusals == []
    refute candidate.reversible?
    assert :remote_write_actuation in candidate.irreversible_edges
    assert :dual_write_side_effects in candidate.irreversible_edges
    assert :brce_actuation_receipt in candidate.required_evidence
  end

  test "telemetry contract refuses raw sensitive and unbounded attributes" do
    candidate = DfCM.evaluate(DfCM.default_graph(), default_assignment(DfCM.default_graph()))
    contract = Observability.contract(candidate)

    assert :receipt_emitted in contract.events
    assert :receipt_sha256 in contract.span_attributes
    assert :raw_query in contract.forbidden_raw_attributes

    assert {:error, sensitive} = Observability.validate_attributes(%{raw_query: "SELECT * WHERE {?s ?p ?o}"})
    assert sensitive.code == :REFUSED_TELEMETRY_SENSITIVE_ATTRIBUTE

    assert {:error, cardinality} = Observability.validate_attributes(%{arbitrary_customer_value: "x"})
    assert cardinality.code == :REFUSED_TELEMETRY_UNBOUNDED_CARDINALITY

    assert :ok =
             Observability.validate_attributes(%{
               stage: :construct,
               result: :ok,
               receipt_sha256: String.duplicate("b", 64)
             })
  end

  test "security graph fences DO from every role except BRCE" do
    refute Security.authorized?(:compiler, :perform_bounded_do)
    refute Security.authorized?(:operator, :perform_bounded_do)
    assert Security.authorized?(:brce_actuator, :perform_bounded_do)

    intent = complete_intent()

    assert {:error, refusal} = Security.admit_do(:operator, intent)
    assert refusal.code == :REFUSED_DO_ROLE

    assert {:error, missing} = Security.admit_do(:brce_actuator, Map.delete(intent, :authority_sha256))
    assert missing.code == :REFUSED_UNRECEIPTED_ACTUATION

    assert {:ok, admitted} = Security.admit_do(:brce_actuator, intent)
    assert admitted.status == :PARTIAL_ALIVE
    assert admitted.standing == :do_intent_admitted_not_executed
  end

  test "resilience contract expands permanent failure corpus" do
    graph = DfCM.default_graph()

    candidate =
      graph
      |> default_assignment()
      |> Map.merge(%{
        deployment_topology: :cellular_multi_region,
        partition_strategy: :hybrid,
        release_strategy: :cell_progressive,
        control_plane: :cellular_federated,
        execution_mode: :receipted_write_runtime,
        observability: :open_telemetry_receipts,
        migration_strategy: :expand_contract,
        disaster_recovery: :active_active,
        consistency_model: :strong
      })
      |> then(&DfCM.evaluate(graph, &1))

    assert candidate.refusals == []
    contract = Resilience.contract(candidate)
    ids = Enum.map(contract.failure_catalog, & &1.id)

    assert :cell_loss in ids
    assert :single_region_loss in ids
    assert :duplicate_delivery in ids
    assert contract.objectives.rpo_seconds == 0
    assert Resilience.error_budget_ms(99.99, 86_400_000) in 8_600..8_700
  end

  test "release plan separates green technical gates from authority" do
    candidate = DfCM.evaluate(DfCM.default_graph(), default_assignment(DfCM.default_graph()))
    plan = Release.plan(candidate, %{artifact: "sha256:deadbeef"})

    evidence =
      Map.new(plan.gates, fn gate ->
        {gate, %{status: :ALIVE, receipt_sha256: String.duplicate("c", 64)}}
      end)

    without_authority = Map.put(evidence, :release_authority, %{authorized?: false, receipt_sha256: String.duplicate("d", 64)})
    result = Release.evaluate(plan, without_authority)
    assert :release_authority in result.failed
    refute result.release_authorized?

    with_authority = Map.put(evidence, :release_authority, %{authorized?: true, receipt_sha256: String.duplicate("d", 64)})
    result = Release.evaluate(plan, with_authority)
    assert result.failed == []
    assert result.release_authorized?
    assert result.status == :PARTIAL_ALIVE
  end

  test "receipt DAG rejects missing parents and produces deterministic replay plan" do
    source = Replay.node(:source, String.duplicate("1", 64), %{tree: "abc"})
    compile = Replay.node(:compile, String.duplicate("1", 64), %{mapping: "xyz"}, parents: [source.id])
    verify = Replay.node(:verify, String.duplicate("1", 64), %{parity: true}, parents: [compile.id])

    assert {:error, missing} = Replay.add(%Replay.DAG{}, compile)
    assert missing.code == :REFUSED_RECEIPT_DAG_MISSING_PARENT

    assert {:ok, dag} = Replay.build([source, compile, verify])
    assert :ok = Replay.verify(dag)
    assert dag.roots == [source.id]
    assert dag.heads == [verify.id]

    assert {:ok, plan} = Replay.plan(dag, verify.id)
    assert plan.nodes == [source.id, compile.id, verify.id]
    assert String.length(plan.plan_sha256) == 64

    same = Replay.compare(%{receipt: "x"}, %{receipt: "x"})
    different = Replay.compare(%{receipt: "x"}, %{receipt: "y"})
    assert same.standing == :REPLAY_MATCH
    assert different.standing == :REPLAY_MISMATCH
  end

  defp default_assignment(graph) do
    Map.new(graph.dimensions, &{&1.id, &1.default})
  end

  defp complete_intent do
    %{
      intent_sha256: String.duplicate("1", 64),
      semantic_subject_sha256: String.duplicate("2", 64),
      authority_sha256: String.duplicate("3", 64),
      pre_state_sha256: String.duplicate("4", 64),
      expected_consequence_sha256: String.duplicate("5", 64),
      idempotency_key_sha256: String.duplicate("6", 64),
      replay_plan_sha256: String.duplicate("7", 64)
    }
  end
end
