# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Production.Observability do
  @moduledoc "Operational telemetry contract derived from a design candidate."

  @spec contract(map(), String.t()) :: map()
  def contract(assignment, subject_sha256) do
    %{
      trace_context: [:trace_id, :span_id, :trace_flags],
      receipt_context: [:semantic_subject_sha256, :compilation_receipt_sha256, :execution_receipt_sha256],
      required_events: [:admit, :construct, :route, :execute, :receipt, :replay, :refusal],
      histograms: [:latency_ms, :queue_ms, :external_engine_ms, :replay_ms],
      counters: [:admitted, :refused, :timeouts, :retries, :failovers],
      gauges: [:inflight, :queue_depth, :healthy_cells],
      semantic_subject_sha256: subject_sha256,
      mode: Map.get(assignment, :observability, :otel),
      forbidden_labels: [:tenant_id, :raw_query, :iri, :secret, :token, :email, :subject_value],
      max_dynamic_label_cardinality: 100
    }
  end

  @spec validate_labels(map()) :: :ok | {:error, map()}
  def validate_labels(labels) when is_map(labels) do
    forbidden = [:tenant_id, :raw_query, :iri, :secret, :token, :email, :subject_value]
    leaked = Enum.filter(Map.keys(labels), &(&1 in forbidden or to_string(&1) in Enum.map(forbidden, &to_string/1)))

    if leaked == [] do
      :ok
    else
      {:error, %{code: :REFUSED_TELEMETRY_SENSITIVE_LABEL, labels: leaked}}
    end
  end
end

defmodule AshR2RML.Production.Security do
  @moduledoc "Least-privilege authority and tenant-isolation contract."

  @spec contract(map()) :: map()
  def contract(assignment) do
    execution_mode = Map.get(assignment, :execution_mode, :compile_only)

    %{
      ambient_authority: false,
      default_network_policy: :deny,
      secret_delivery: Map.get(assignment, :secret_delivery, :workload_identity),
      tenant_isolation: Map.get(assignment, :tenancy_model, :schema_per_tenant),
      residency: Map.get(assignment, :data_residency, :regional),
      roles: %{
        compiler: [:read_semantic_input, :construct_ir],
        ggen_manufacturer: [:read_manufacturing_input, :write_generated_projection],
        verifier: [:read_projection, :read_runtime_observation],
        semantic_runtime: if(execution_mode == :compile_only, do: [], else: [:read_semantic_runtime]),
        brce_actuator: if(execution_mode == :receipted_write_runtime, do: [:receipted_do], else: [])
      },
      invariants: [
        :cross_tenant_default_deny,
        :authority_not_derived_from_model_output,
        :secret_values_never_in_receipts,
        :do_only_through_brce,
        :residency_checked_before_routing
      ]
    }
  end
end

defmodule AshR2RML.Production.Resilience do
  @moduledoc "Failure, recovery and replay contract."

  @spec contract(map(), map()) :: map()
  def contract(assignment, objectives) do
    %{
      topology: Map.get(assignment, :deployment_topology, :active_passive),
      recovery_strategy: Map.get(assignment, :recovery_strategy, :failover_replay),
      rpo_seconds: Map.get(objectives, :max_recovery_point_seconds, 60),
      rto_seconds: Map.get(objectives, :max_recovery_time_seconds, 300),
      required_faults: [
        :beam_process_crash,
        :external_worker_crash,
        :obda_timeout,
        :database_connection_loss,
        :zone_loss,
        :region_loss,
        :stale_route,
        :duplicate_delivery,
        :partial_generation,
        :receipt_corruption
      ],
      recovery_invariants: [
        :idempotent_retry,
        :bounded_retry,
        :deterministic_replay,
        :receipt_chain_continuity,
        :no_authority_escalation_during_recovery
      ]
    }
  end
end

defmodule AshR2RML.Production.Release do
  @moduledoc "Progressive delivery and rollback contract."

  @spec contract(map()) :: map()
  def contract(assignment) do
    strategy = Map.get(assignment, :release_strategy, :canary)

    %{
      strategy: strategy,
      migration_strategy: Map.get(assignment, :migration_strategy, :expand_contract),
      stages: stages(strategy),
      preconditions: [
        :exact_head_compile,
        :dependency_audit,
        :sbom,
        :signature,
        :provenance,
        :migration_dry_run,
        :rollback_plan
      ],
      abort_on: [:error_budget_burn, :semantic_parity_failure, :receipt_mismatch, :tenant_isolation_failure],
      rollback_requires_new_receipt: true
    }
  end

  defp stages(:rolling), do: [%{name: :rolling, percent: 100}]
  defp stages(:blue_green), do: [%{name: :green_shadow, percent: 0}, %{name: :green_cutover, percent: 100}]
  defp stages(:canary), do: [%{name: :canary, percent: 1}, %{name: :expand, percent: 10}, %{name: :majority, percent: 50}, %{name: :complete, percent: 100}]
  defp stages(:cell_progressive), do: [%{name: :first_cell, percent: 1}, %{name: :one_region, percent: 10}, %{name: :half_cells, percent: 50}, %{name: :all_cells, percent: 100}]
end
