# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.Observability do
  @moduledoc "Stable observability contract derived from an admitted DfCM candidate."

  @events [
    :admit_started,
    :admit_completed,
    :admit_refused,
    :construct_started,
    :construct_completed,
    :construct_refused,
    :ggen_plan_built,
    :ggen_materialization_observed,
    :query_started,
    :query_completed,
    :query_refused,
    :do_requested,
    :do_admitted,
    :do_refused,
    :receipt_emitted,
    :replay_started,
    :replay_completed,
    :replay_mismatch,
    :dependency_degraded,
    :dependency_recovered,
    :failover_started,
    :failover_completed,
    :release_gate_evaluated
  ]

  @metrics [
    %{name: :admission_duration_ms, type: :histogram, unit: :millisecond, labels: [:result]},
    %{name: :construction_duration_ms, type: :histogram, unit: :millisecond, labels: [:result, :projection]},
    %{name: :query_duration_ms, type: :histogram, unit: :millisecond, labels: [:strategy, :result]},
    %{name: :queue_duration_ms, type: :histogram, unit: :millisecond, labels: [:work_class]},
    %{name: :active_operations, type: :gauge, unit: :operation, labels: [:work_class]},
    %{name: :refusal_total, type: :counter, unit: :refusal, labels: [:code, :stage]},
    %{name: :projection_bytes, type: :histogram, unit: :byte, labels: [:projection]},
    %{name: :external_result_rows, type: :histogram, unit: :row, labels: [:strategy]},
    %{name: :external_result_bytes, type: :histogram, unit: :byte, labels: [:strategy]},
    %{name: :receipt_total, type: :counter, unit: :receipt, labels: [:standing]},
    %{name: :replay_total, type: :counter, unit: :replay, labels: [:result]},
    %{name: :semantic_drift_total, type: :counter, unit: :change, labels: [:classification]},
    %{name: :dependency_health, type: :gauge, unit: :state, labels: [:dependency]},
    %{name: :failover_duration_ms, type: :histogram, unit: :millisecond, labels: [:failure_domain]},
    %{name: :tenant_throttle_total, type: :counter, unit: :operation, labels: [:class]},
    %{name: :release_gate_total, type: :counter, unit: :gate, labels: [:gate, :result]}
  ]

  @bounded_attributes [
    :service_name,
    :service_version,
    :environment,
    :region,
    :cell,
    :stage,
    :result,
    :standing,
    :refusal_code,
    :projection,
    :query_strategy,
    :capability,
    :deployment_topology,
    :release_strategy,
    :compliance_profile
  ]

  @hash_attributes [
    :semantic_subject_sha256,
    :mapping_sha256,
    :query_sha256,
    :receipt_sha256,
    :authority_sha256,
    :candidate_sha256,
    :artifact_sha256,
    :environment_sha256
  ]

  @forbidden_raw_attributes [
    :tenant_id,
    :raw_query,
    :raw_iri,
    :raw_subject,
    :secret,
    :authorization_header,
    :database_url,
    :raw_external_output
  ]

  def events, do: @events
  def metrics, do: @metrics
  def bounded_attributes, do: @bounded_attributes
  def hash_attributes, do: @hash_attributes
  def forbidden_raw_attributes, do: @forbidden_raw_attributes

  @doc "Build the observability contract for one DfCM candidate."
  def contract(candidate) do
    assignment = assignment(candidate)

    %{
      version: "fortune5-observability-v1",
      mode: Map.get(assignment, :observability, :open_telemetry_receipts),
      events: @events,
      metrics: @metrics,
      span_attributes: @bounded_attributes ++ @hash_attributes,
      forbidden_raw_attributes: @forbidden_raw_attributes,
      propagation: %{
        w3c_trace_context?: true,
        baggage_allowed?: false,
        semantic_subject_hash?: true,
        receipt_hash?: true,
        candidate_hash?: true
      },
      sampling: %{
        refusal: :always,
        do: :always,
        replay_mismatch: :always,
        admission_success: {:ratio, 0.1},
        read_success: {:ratio, 0.01}
      },
      retention_classes: %{
        operational_metrics: :short,
        traces: :bounded,
        authority_receipts: :governed,
        replay_receipts: :governed
      },
      cardinality_policy: %{
        raw_tenant_labels?: false,
        raw_iri_labels?: false,
        raw_query_labels?: false,
        hashes_allowed?: true,
        bounded_enum_labels?: true
      }
    }
  end

  @doc "Fail closed when a telemetry payload contains forbidden raw attributes."
  def validate_attributes(attributes) when is_map(attributes) do
    forbidden =
      @forbidden_raw_attributes
      |> Enum.filter(fn key ->
        value = Map.get(attributes, key, Map.get(attributes, Atom.to_string(key)))
        not is_nil(value)
      end)

    unbounded =
      attributes
      |> Map.keys()
      |> Enum.map(&normalize_key/1)
      |> Enum.reject(&(&1 in @bounded_attributes or &1 in @hash_attributes or &1 in @forbidden_raw_attributes))

    cond do
      forbidden != [] ->
        {:error,
         %{
           code: :REFUSED_TELEMETRY_SENSITIVE_ATTRIBUTE,
           subject: :telemetry,
           evidence: %{forbidden: forbidden}
         }}

      unbounded != [] ->
        {:error,
         %{
           code: :REFUSED_TELEMETRY_UNBOUNDED_CARDINALITY,
           subject: :telemetry,
           evidence: %{unbounded: unbounded}
         }}

      true ->
        :ok
    end
  end

  defp assignment(%{assignment: assignment}) when is_map(assignment), do: assignment
  defp assignment(assignment) when is_map(assignment), do: assignment
  defp normalize_key(key) when is_binary(key), do: Enum.find(@bounded_attributes ++ @hash_attributes ++ @forbidden_raw_attributes, &(Atom.to_string(&1) == key)) || key
  defp normalize_key(key), do: key
end

defmodule AshR2RML.Fortune5.Security do
  @moduledoc "Least-privilege authority graph for SELECT, CONSTRUCT, DO and verification."

  @roles %{
    semantic_author => [:submit_profile, :submit_shape, :inspect_refusal],
    compiler => [:read_admitted_semantics, :construct_mapping, :construct_projection, :emit_construct_receipt],
    ggen_manufacturer => [:read_construct_plan, :materialize_projection, :hash_staged_artifact, :emit_manufacture_receipt],
    query_verifier => [:read_mapping, :execute_bounded_query, :compare_observation, :emit_verification_receipt],
    release_verifier => [:read_artifact, :read_evidence, :evaluate_release_gate],
    operator => [:read_health, :read_receipt, :request_do],
    brce_actuator => [:consume_admitted_do_intent, :perform_bounded_do, :emit_do_receipt],
    cutover_authority => [:authorize_cutover],
    auditor => [:read_redacted_receipt, :replay_read_only_evidence]
  }

  @ambient_forbidden [
    {:semantic_author, :perform_bounded_do},
    {:compiler, :materialize_projection},
    {:compiler, :perform_bounded_do},
    {:ggen_manufacturer, :perform_bounded_do},
    {:query_verifier, :perform_bounded_do},
    {:release_verifier, :perform_bounded_do},
    {:operator, :perform_bounded_do},
    {:auditor, :perform_bounded_do},
    {:brce_actuator, :authorize_cutover}
  ]

  @doc "Role/permission graph."
  def roles, do: @roles
  def ambient_forbidden, do: @ambient_forbidden

  @doc "Build candidate-specific security contract."
  def contract(candidate) do
    assignment = assignment(candidate)

    %{
      version: "fortune5-security-v1",
      workload_identity: Map.get(assignment, :workload_identity, :spiffe),
      secret_provider: Map.get(assignment, :secret_provider, :external_secrets_operator),
      network_boundary: Map.get(assignment, :network_boundary, :zero_trust_mesh),
      tenancy_model: Map.get(assignment, :tenancy_model, :shared_schema),
      runtime_isolation: Map.get(assignment, :runtime_isolation, :cell_pool),
      roles: @roles,
      ambient_forbidden: @ambient_forbidden,
      invariants: [
        :no_secret_in_generated_artifact,
        :no_secret_in_receipt,
        :no_raw_external_output_in_receipt,
        :no_model_output_execution_authority,
        :no_template_execution_authority,
        :no_hook_actuation,
        :brce_only_do,
        :separate_cutover_authority,
        :tenant_context_required,
        :deny_cross_tenant_by_default
      ],
      supply_chain: %{
        sbom_required?: true,
        signed_artifacts?: true,
        provenance_attestation?: true,
        vulnerability_gate?: true,
        immutable_digest_reference?: true
      }
    }
  end

  @doc "Authorize a permission for a role. This is policy inspection, not actuation."
  def authorized?(role, permission) do
    permission in Map.get(@roles, role, []) and {role, permission} not in @ambient_forbidden
  end

  @doc "Admit a DO intent only for the BRCE actuator with complete receipt binding."
  def admit_do(role, intent) when is_map(intent) do
    required = [
      :intent_sha256,
      :semantic_subject_sha256,
      :authority_sha256,
      :pre_state_sha256,
      :expected_consequence_sha256,
      :idempotency_key_sha256,
      :replay_plan_sha256
    ]

    missing = Enum.reject(required, &present?(value(intent, &1)))

    cond do
      role != :brce_actuator ->
        {:error, refusal(:REFUSED_DO_ROLE, role, %{required_role: :brce_actuator})}

      missing != [] ->
        {:error, refusal(:REFUSED_UNRECEIPTED_ACTUATION, :do_intent, %{missing: missing})}

      true ->
        {:ok,
         %{
           status: :PARTIAL_ALIVE,
           standing: :do_intent_admitted_not_executed,
           intent_sha256: value(intent, :intent_sha256),
           admission_sha256: sha256(intent),
           replay_required?: true
         }}
    end
  end

  defp refusal(code, subject, evidence) do
    %{code: code, subject: subject, detail: "Fortune-5 authority admission refused", evidence: evidence}
  end

  defp assignment(%{assignment: assignment}) when is_map(assignment), do: assignment
  defp assignment(assignment) when is_map(assignment), do: assignment
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp present?(value), do: is_binary(value) and value != ""

  defp sha256(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end
end

defmodule AshR2RML.Fortune5.Resilience do
  @moduledoc "Failure-domain and disaster-recovery contract for DfCM candidates."

  @failure_catalog [
    %{id: :worker_crash, domain: :process, injection: :kill_worker, expected: :supervised_recovery},
    %{id: :scheduler_overload, domain: :process, injection: :queue_saturation, expected: :backpressure},
    %{id: :memory_pressure, domain: :process, injection: :memory_limit, expected: :bounded_failure},
    %{id: :postgres_connection_loss, domain: :database, injection: :drop_connections, expected: :readiness_degraded},
    %{id: :postgres_primary_loss, domain: :database, injection: :stop_primary, expected: :failover_or_refusal},
    %{id: :ontop_process_loss, domain: :obda, injection: :kill_engine, expected: :topology_degraded},
    %{id: :sparql_endpoint_timeout, domain: :obda, injection: :latency, expected: :bounded_timeout},
    %{id: :sparql_oversized_result, domain: :obda, injection: :oversized_result, expected: :row_or_byte_refusal},
    %{id: :registry_unavailable, domain: :supply_chain, injection: :deny_registry, expected: :cached_or_replica_resolution},
    %{id: :secret_provider_unavailable, domain: :security, injection: :deny_secret_provider, expected: :fail_closed},
    %{id: :identity_provider_unavailable, domain: :security, injection: :deny_identity_provider, expected: :fail_closed},
    %{id: :single_zone_loss, domain: :infrastructure, injection: :disable_zone, expected: :zonal_failover},
    %{id: :single_region_loss, domain: :infrastructure, injection: :disable_region, expected: :regional_failover},
    %{id: :cell_loss, domain: :infrastructure, injection: :disable_cell, expected: :cellular_containment},
    %{id: :network_partition, domain: :network, injection: :partition, expected: :consistency_policy},
    %{id: :packet_loss, domain: :network, injection: :packet_loss, expected: :bounded_retry},
    %{id: :clock_skew, domain: :runtime, injection: :clock_skew, expected: :receipt_identity_stable},
    %{id: :duplicate_delivery, domain: :runtime, injection: :duplicate_intent, expected: :idempotent_do},
    %{id: :partial_artifact_write, domain: :ggen, injection: :interrupt_materialization, expected: :atomic_publication},
    %{id: :semantic_drift, domain: :semantic, injection: :change_profile, expected: :drift_classification},
    %{id: :mapping_corruption, domain: :semantic, injection: :alter_mapping, expected: :hash_mismatch_refusal},
    %{id: :receipt_corruption, domain: :governance, injection: :alter_receipt, expected: :replay_mismatch},
    %{id: :cross_tenant_probe, domain: :tenancy, injection: :foreign_tenant_context, expected: :deny},
    %{id: :residency_violation_probe, domain: :tenancy, injection: :foreign_region_route, expected: :deny}
  ]

  def failures, do: @failure_catalog

  @doc "Candidate-specific resilience and DR contract."
  def contract(candidate) do
    a = assignment(candidate)

    %{
      version: "fortune5-resilience-v1",
      deployment_topology: Map.get(a, :deployment_topology),
      availability_model: Map.get(a, :availability_model),
      disaster_recovery: Map.get(a, :disaster_recovery),
      partition_strategy: Map.get(a, :partition_strategy),
      control_plane: Map.get(a, :control_plane),
      failure_catalog: required_failures(a),
      objectives: objectives(a),
      retry_policy: %{
        bounded?: true,
        jitter?: true,
        max_attempts: 3,
        mutation_retry_requires_idempotency_key?: true
      },
      circuit_breakers: %{
        external_sparql?: true,
        ontop?: true,
        postgres?: true,
        secret_provider?: true,
        identity_provider?: true
      },
      degradation: %{
        optional_query_topology_may_degrade?: true,
        semantic_admission_may_not_be_bypassed?: true,
        do_authority_may_not_be_bypassed?: true
      }
    }
  end

  @doc "Compute availability error budget in milliseconds for a period."
  def error_budget_ms(availability_percent, period_ms)
      when is_number(availability_percent) and is_integer(period_ms) and period_ms > 0 do
    unavailable_fraction = max(0.0, 1.0 - availability_percent / 100.0)
    trunc(period_ms * unavailable_fraction)
  end

  defp required_failures(a) do
    @failure_catalog
    |> Enum.filter(fn scenario ->
      case scenario.id do
        :single_region_loss -> Map.get(a, :deployment_topology) != :single_region
        :cell_loss -> Map.get(a, :deployment_topology) == :cellular_multi_region
        :duplicate_delivery -> Map.get(a, :execution_mode) == :receipted_write_runtime
        :cross_tenant_probe -> true
        :residency_violation_probe -> Map.get(a, :data_residency) != :unrestricted
        _ -> true
      end
    end)
  end

  defp objectives(a) do
    case Map.get(a, :disaster_recovery) do
      :backup_restore -> %{rpo_seconds: 3600, rto_seconds: 14_400, mode: :restore}
      :warm_standby -> %{rpo_seconds: 300, rto_seconds: 1800, mode: :promote}
      :hot_standby -> %{rpo_seconds: 30, rto_seconds: 300, mode: :failover}
      :active_active -> %{rpo_seconds: 0, rto_seconds: 60, mode: :route}
      _ -> %{rpo_seconds: :UNKNOWN, rto_seconds: :UNKNOWN, mode: :UNKNOWN}
    end
  end

  defp assignment(%{assignment: assignment}) when is_map(assignment), do: assignment
  defp assignment(assignment) when is_map(assignment), do: assignment
end

defmodule AshR2RML.Fortune5.Release do
  @moduledoc "Progressive release admission. Release authority remains external."

  @gates [
    :exact_source_identity,
    :compile_warnings_as_errors,
    :focused_semantic_tests,
    :full_test_suite,
    :dialyzer,
    :security_scan,
    :sbom_present,
    :artifact_signature_verified,
    :provenance_verified,
    :deterministic_ggen_two_pass,
    :obda_crown,
    :semantic_parity,
    :capacity_evidence,
    :failure_injection_evidence,
    :rollback_replay,
    :release_authority
  ]

  def gates, do: @gates

  @doc "Construct a release plan for a candidate and artifact manifest."
  def plan(candidate, artifact_manifest \\ %{}) do
    a = assignment(candidate)
    strategy = Map.get(a, :release_strategy, :canary)

    %{
      version: "fortune5-release-v1",
      strategy: strategy,
      artifact_manifest_sha256: sha256(artifact_manifest),
      gates: @gates,
      phases: phases(strategy),
      rollback: rollback(strategy),
      invariants: [
        :immutable_artifact_digest,
        :no_rebuild_between_rings,
        :no_schema_destructive_change_before_expand_contract_completion,
        :release_gate_evidence_bound_to_exact_head,
        :cutover_authority_separate_from_green_tests
      ]
    }
  end

  @doc "Evaluate release gates without granting release authority."
  def evaluate(plan, evidence) when is_map(plan) and is_map(evidence) do
    results =
      Map.new(plan.gates, fn gate ->
        observation = Map.get(evidence, gate, Map.get(evidence, Atom.to_string(gate)))
        {gate, admitted_gate?(gate, observation)}
      end)

    failed = results |> Enum.reject(fn {_gate, ok?} -> ok? end) |> Enum.map(&elem(&1, 0))

    %{
      status: if(failed == [], do: :PARTIAL_ALIVE, else: :BLOCKED),
      standing: if(failed == [], do: :release_gates_satisfied_pending_actuation, else: :release_gates_incomplete),
      passed: results |> Enum.filter(fn {_gate, ok?} -> ok? end) |> Enum.map(&elem(&1, 0)),
      failed: failed,
      evaluation_sha256: sha256({plan, evidence}),
      release_authorized?: failed == [] and release_authority?(evidence)
    }
  end

  defp admitted_gate?(:release_authority, observation), do: authority_observation?(observation)

  defp admitted_gate?(_gate, observation) when is_map(observation) do
    status = Map.get(observation, :status, Map.get(observation, "status"))
    receipt = Map.get(observation, :receipt_sha256, Map.get(observation, "receipt_sha256"))
    status in [:ALIVE, :VERIFIED, "ALIVE", "VERIFIED"] and present?(receipt)
  end

  defp admitted_gate?(_gate, _), do: false

  defp release_authority?(evidence), do: authority_observation?(Map.get(evidence, :release_authority, Map.get(evidence, "release_authority")))

  defp authority_observation?(observation) when is_map(observation) do
    authorized = Map.get(observation, :authorized?, Map.get(observation, "authorized?", false))
    receipt = Map.get(observation, :receipt_sha256, Map.get(observation, "receipt_sha256"))
    authorized == true and present?(receipt)
  end

  defp authority_observation?(_), do: false

  defp phases(:rolling), do: [%{name: :rolling, traffic: :incremental, stop_on_gate_failure?: true}]

  defp phases(:blue_green) do
    [
      %{name: :green_shadow, traffic_percent: 0, compare_receipts?: true},
      %{name: :green_probe, traffic_percent: 1, compare_receipts?: true},
      %{name: :green_cutover, traffic_percent: 100, requires_authority?: true}
    ]
  end

  defp phases(:canary) do
    [
      %{name: :shadow, traffic_percent: 0, minimum_observations: 1_000},
      %{name: :canary_1, traffic_percent: 1, minimum_observations: 10_000},
      %{name: :canary_5, traffic_percent: 5, minimum_observations: 50_000},
      %{name: :canary_25, traffic_percent: 25, minimum_observations: 100_000},
      %{name: :canary_50, traffic_percent: 50, minimum_observations: 100_000},
      %{name: :global, traffic_percent: 100, requires_authority?: true}
    ]
  end

  defp phases(:cell_progressive) do
    [
      %{name: :test_cell, cells: 1, minimum_observations: 10_000},
      %{name: :region_canary, regions: 1, cell_fraction: 0.1},
      %{name: :region_full, regions: 1, cell_fraction: 1.0},
      %{name: :multi_region, region_fraction: 0.25},
      %{name: :global, region_fraction: 1.0, requires_authority?: true}
    ]
  end

  defp phases(_), do: phases(:canary)

  defp rollback(strategy) do
    %{
      strategy: strategy,
      preserve_previous_artifact?: true,
      preserve_previous_mapping?: true,
      preserve_previous_schema_contract?: true,
      automatic_only_before_irreversible_migration?: true,
      replay_required_after_rollback?: true
    }
  end

  defp assignment(%{assignment: assignment}) when is_map(assignment), do: assignment
  defp assignment(assignment) when is_map(assignment), do: assignment
  defp present?(value), do: is_binary(value) and value != ""

  defp sha256(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end
end

defmodule AshR2RML.Fortune5.Replay do
  @moduledoc "Content-addressed receipt DAG and deterministic replay planner."

  defmodule Node do
    @moduledoc "One immutable evidence node."
    @enforce_keys [:kind, :subject_sha256, :payload_sha256]
    defstruct [:id, :kind, :subject_sha256, :payload_sha256, :environment_sha256, parents: [], metadata: %{}]
  end

  defmodule DAG do
    @moduledoc "Receipt DAG with no ambient edges."
    defstruct version: "fortune5-receipt-dag-v1", nodes: %{}, roots: [], heads: []
  end

  @doc "Create a content-addressed node."
  def node(kind, subject_sha256, payload, opts \\ []) do
    parents = Keyword.get(opts, :parents, []) |> Enum.sort()
    environment = Keyword.get(opts, :environment_sha256)
    metadata = Keyword.get(opts, :metadata, %{})
    payload_sha256 = sha256(payload)

    base = %Node{
      kind: kind,
      subject_sha256: subject_sha256,
      payload_sha256: payload_sha256,
      environment_sha256: environment,
      parents: parents,
      metadata: metadata
    }

    %{base | id: sha256(Map.from_struct(base))}
  end

  @doc "Add a node only when all declared parents already exist."
  def add(%DAG{} = dag, %Node{} = node) do
    missing = Enum.reject(node.parents, &Map.has_key?(dag.nodes, &1))

    if missing == [] do
      nodes = Map.put(dag.nodes, node.id, node)
      referenced = nodes |> Map.values() |> Enum.flat_map(& &1.parents) |> MapSet.new()
      roots = nodes |> Map.values() |> Enum.filter(&(&1.parents == [])) |> Enum.map(& &1.id) |> Enum.sort()
      heads = nodes |> Map.keys() |> Enum.reject(&MapSet.member?(referenced, &1)) |> Enum.sort()
      {:ok, %{dag | nodes: nodes, roots: roots, heads: heads}}
    else
      {:error,
       %{
         code: :REFUSED_RECEIPT_DAG_MISSING_PARENT,
         subject: node.id,
         evidence: %{missing: missing}
       }}
    end
  end

  @doc "Build a DAG from already topologically ordered nodes."
  def build(nodes) do
    Enum.reduce_while(nodes, {:ok, %DAG{}}, fn node, {:ok, dag} ->
      case add(dag, node) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Verify node identities, parent closure and acyclicity."
  def verify(%DAG{} = dag) do
    identity_errors =
      dag.nodes
      |> Enum.flat_map(fn {id, node} ->
        expected = node |> Map.from_struct() |> Map.put(:id, nil) |> sha256()
        if id == node.id and id == expected, do: [], else: [{:identity_mismatch, id, expected}]
      end)

    parent_errors =
      dag.nodes
      |> Enum.flat_map(fn {id, node} ->
        node.parents
        |> Enum.reject(&Map.has_key?(dag.nodes, &1))
        |> Enum.map(&{:missing_parent, id, &1})
      end)

    cycle_errors =
      dag.nodes
      |> Map.keys()
      |> Enum.flat_map(fn id -> if cycle?(dag, id, MapSet.new(), MapSet.new()), do: [{:cycle, id}], else: [] end)
      |> Enum.uniq()

    errors = identity_errors ++ parent_errors ++ cycle_errors
    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc "Create a replay plan for one receipt head."
  def plan(%DAG{} = dag, head_id) do
    with :ok <- verify(dag),
         true <- Map.has_key?(dag.nodes, head_id) do
      ordered = ancestors(dag, head_id, MapSet.new()) |> MapSet.to_list() |> topological(dag)

      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :replay_plan_constructed,
         head: head_id,
         nodes: ordered,
         required_payloads: Enum.map(ordered, &dag.nodes[&1].payload_sha256),
         required_environments:
           ordered
           |> Enum.map(&dag.nodes[&1].environment_sha256)
           |> Enum.reject(&is_nil/1)
           |> Enum.uniq()
           |> Enum.sort(),
         plan_sha256: sha256({head_id, ordered})
       }}
    else
      false -> {:error, %{code: :UNKNOWN_RECEIPT_HEAD, subject: head_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Compare an expected and observed replay receipt."
  def compare(expected, observed) when is_map(expected) and is_map(observed) do
    expected_hash = sha256(expected)
    observed_hash = sha256(observed)

    %{
      status: if(expected_hash == observed_hash, do: :ALIVE, else: :BLOCKED),
      standing: if(expected_hash == observed_hash, do: :REPLAY_MATCH, else: :REPLAY_MISMATCH),
      expected_sha256: expected_hash,
      observed_sha256: observed_hash
    }
  end

  defp cycle?(dag, id, visited, stack) do
    cond do
      MapSet.member?(stack, id) -> true
      MapSet.member?(visited, id) -> false
      true ->
        node = dag.nodes[id]
        visited = MapSet.put(visited, id)
        stack = MapSet.put(stack, id)
        Enum.any?(node.parents, &cycle?(dag, &1, visited, stack))
    end
  end

  defp ancestors(dag, id, acc) do
    if MapSet.member?(acc, id) do
      acc
    else
      acc = MapSet.put(acc, id)
      Enum.reduce(dag.nodes[id].parents, acc, &ancestors(dag, &1, &2))
    end
  end

  defp topological(ids, dag) do
    set = MapSet.new(ids)
    do_topological(set, dag, [])
  end

  defp do_topological(set, dag, acc) do
    if MapSet.size(set) == 0 do
      acc
    else
      emitted = MapSet.new(acc)

      ready =
        set
        |> MapSet.to_list()
        |> Enum.filter(fn id -> Enum.all?(dag.nodes[id].parents, &MapSet.member?(emitted, &1)) end)
        |> Enum.sort()

      case ready do
        [] -> acc ++ Enum.sort(MapSet.to_list(set))
        _ ->
          next = Enum.reduce(ready, set, &MapSet.delete(&2, &1))
          do_topological(next, dag, acc ++ ready)
      end
    end
  end

  defp sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {canonical(key), canonical(value)} end)
    |> Enum.sort_by(fn {key, _} -> :erlang.term_to_binary(key, [:deterministic]) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(other), do: other
end
