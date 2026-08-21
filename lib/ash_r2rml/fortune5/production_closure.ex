# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.ProductionClosure do
  @moduledoc """
  Fortune-5 production admission contract for AshR2RML.

  This module is intentionally SELECT/CONSTRUCT-oriented. It does not start
  infrastructure, run migrations, write files, mutate data, or grant cutover
  authority. It makes the production closure explicit enough for Spark, Reactor,
  Igniter, ggen, CI, and operator receipts to converge on one auditable boundary.
  """

  defmodule Refusal do
    @moduledoc "Typed Fortune-5 production refusal."
    defstruct [:code, :subject, :detail, evidence: %{}]
  end

  defmodule Contract do
    @moduledoc "Admitted production target before runtime evidence is attached."

    defstruct version: "fortune5-dfcm-v1",
              slo: %{
                p99_cold_path_ms: 500,
                max_queue_ms: 50,
                timeout_ms: 30_000
              },
              capacity: %{
                min_concurrent_operations: 1_000_000,
                horizontal_scaling?: true,
                partitioned_execution?: true,
                backpressure?: true
              },
              availability: %{
                min_regions: 2,
                min_availability_zones_per_region: 3,
                rolling_deploys?: true,
                failover_tested?: true,
                disaster_recovery_tested?: true
              },
              telemetry: %{
                trace_context?: true,
                semantic_receipt_hash?: true,
                p95_p99_histograms?: true,
                decision_log?: true,
                emitted_events: [:admit, :construct, :do, :receipt, :replay, :refusal]
              },
              security: %{
                least_privilege?: true,
                no_ambient_authority?: true,
                secrets_externalized?: true,
                tenant_isolation?: true,
                signed_release?: true,
                sbom_required?: true,
                vulnerability_gate?: true
              },
              operations: %{
                otp_supervision?: true,
                fault_isolation?: true,
                deterministic_recovery?: true,
                replay?: true,
                idempotency_keys?: true,
                schema_validation?: true,
                shacl_validation?: true,
                migration_dry_run?: true,
                rollback_plan?: true
              },
              topology_candidates: [
                :single_region_read_only,
                :multi_region_active_passive,
                :multi_region_active_active,
                :cellular_multi_region
              ],
              selected_topology: :multi_region_active_passive,
              authority: %{
                select_construct_do_separated?: true,
                brce_required_for_do?: true,
                cutover_authority_receipt_sha256: nil
              },
              evidence: %{
                source_constructed?: true,
                exact_subject_runtime_observed?: false,
                stress_1m_concurrency_observed?: false,
                exact_head_ci_sha256: nil,
                obda_crown_receipt_sha256: nil
              },
              receipts: %{}
  end

  defmodule Receipt do
    @moduledoc "Deterministic admission receipt for the production contract."

    defstruct [
      :status,
      :standing,
      :contract_sha256,
      :receipt_sha256,
      :production_ready?,
      admitted_checks: [],
      blocked_checks: [],
      topology_candidates: [],
      selected_topology: nil,
      refusals: []
    ]
  end

  @hard_checks [
    :slo_p99_cold_path,
    :slo_queue_bound,
    :capacity_concurrency,
    :capacity_horizontal_scaling,
    :capacity_partitioned_execution,
    :capacity_backpressure,
    :availability_regions,
    :availability_zones,
    :availability_rolling_deploys,
    :availability_failover,
    :availability_disaster_recovery,
    :telemetry_trace_context,
    :telemetry_receipt_hash,
    :telemetry_histograms,
    :telemetry_decision_log,
    :security_least_privilege,
    :security_no_ambient_authority,
    :security_externalized_secrets,
    :security_tenant_isolation,
    :security_signed_release,
    :security_sbom,
    :security_vulnerability_gate,
    :operations_otp_supervision,
    :operations_fault_isolation,
    :operations_deterministic_recovery,
    :operations_replay,
    :operations_idempotency,
    :operations_schema_validation,
    :operations_shacl_validation,
    :operations_migration_dry_run,
    :operations_rollback_plan,
    :authority_select_construct_do,
    :authority_brce_required,
    :topology_selected_candidate
  ]

  @runtime_checks [
    :runtime_exact_subject_observed,
    :runtime_1m_concurrency_observed,
    :runtime_exact_head_ci,
    :runtime_obda_crown,
    :authority_cutover_receipt
  ]

  @doc "Return the default Fortune-5 DfCM production contract."
  def default_contract, do: %Contract{}

  @doc "Admit a production contract without pretending construction equals runtime evidence."
  def admit(contract \\ default_contract()) do
    contract = normalize(contract)
    hard_failures = failed_hard_checks(contract)
    runtime_failures = failed_runtime_checks(contract)
    receipt = build_receipt(contract, hard_failures, runtime_failures)

    if hard_failures == [] do
      {:ok, receipt}
    else
      {:error, receipt}
    end
  end

  @doc "True only when hard production checks and runtime/cutover evidence are both present."
  def production_ready?(contract) do
    case admit(contract) do
      {:ok, %Receipt{production_ready?: true}} -> true
      _ -> false
    end
  end

  @doc "Authorize one DO operation only when BRCE identity and replay evidence are present."
  def authorize_do(contract \\ default_contract(), request) when is_map(request) do
    contract = normalize(contract)

    required = [
      :brce_receipt_sha256,
      :authority_sha256,
      :pre_state_sha256,
      :post_state_sha256,
      :replay_plan_sha256
    ]

    missing = Enum.reject(required, &present?(Map.get(request, &1) || Map.get(request, Atom.to_string(&1))))

    cond do
      contract.authority[:brce_required_for_do?] != true ->
        {:error,
         refusal(:REFUSED_AUTHORITY, :do, "DO authority requires BRCE in Fortune-5 mode", %{
           required: :brce
         })}

      missing != [] ->
        {:error,
         refusal(:REFUSED_UNRECEIPTED_ACTUATION, :do, "DO request is missing required BRCE fields", %{
           missing: missing
         })}

      true ->
        {:ok,
         %{
           status: :PARTIAL_ALIVE,
           standing: :brce_do_admitted,
           do_receipt_sha256: sha256(request),
           replay_required?: true
         }}
    end
  end

  @doc "All production falsifiers tracked by this contract."
  def falsifiers, do: @hard_checks ++ @runtime_checks

  @doc "Deterministic hash of any production closure term."
  def sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp normalize(%Contract{} = contract), do: contract

  defp normalize(map) when is_map(map) do
    base = Map.from_struct(default_contract())

    base
    |> deep_merge(atomize_keys(map))
    |> then(&struct(Contract, &1))
  end

  defp normalize(keyword) when is_list(keyword), do: keyword |> Map.new() |> normalize()

  defp failed_hard_checks(contract) do
    checks = %{
      slo_p99_cold_path: get_in(contract.slo, [:p99_cold_path_ms]) <= 500,
      slo_queue_bound: get_in(contract.slo, [:max_queue_ms]) <= 50,
      capacity_concurrency: get_in(contract.capacity, [:min_concurrent_operations]) >= 1_000_000,
      capacity_horizontal_scaling: contract.capacity[:horizontal_scaling?] == true,
      capacity_partitioned_execution: contract.capacity[:partitioned_execution?] == true,
      capacity_backpressure: contract.capacity[:backpressure?] == true,
      availability_regions: get_in(contract.availability, [:min_regions]) >= 2,
      availability_zones: get_in(contract.availability, [:min_availability_zones_per_region]) >= 3,
      availability_rolling_deploys: contract.availability[:rolling_deploys?] == true,
      availability_failover: contract.availability[:failover_tested?] == true,
      availability_disaster_recovery: contract.availability[:disaster_recovery_tested?] == true,
      telemetry_trace_context: contract.telemetry[:trace_context?] == true,
      telemetry_receipt_hash: contract.telemetry[:semantic_receipt_hash?] == true,
      telemetry_histograms: contract.telemetry[:p95_p99_histograms?] == true,
      telemetry_decision_log: contract.telemetry[:decision_log?] == true,
      security_least_privilege: contract.security[:least_privilege?] == true,
      security_no_ambient_authority: contract.security[:no_ambient_authority?] == true,
      security_externalized_secrets: contract.security[:secrets_externalized?] == true,
      security_tenant_isolation: contract.security[:tenant_isolation?] == true,
      security_signed_release: contract.security[:signed_release?] == true,
      security_sbom: contract.security[:sbom_required?] == true,
      security_vulnerability_gate: contract.security[:vulnerability_gate?] == true,
      operations_otp_supervision: contract.operations[:otp_supervision?] == true,
      operations_fault_isolation: contract.operations[:fault_isolation?] == true,
      operations_deterministic_recovery: contract.operations[:deterministic_recovery?] == true,
      operations_replay: contract.operations[:replay?] == true,
      operations_idempotency: contract.operations[:idempotency_keys?] == true,
      operations_schema_validation: contract.operations[:schema_validation?] == true,
      operations_shacl_validation: contract.operations[:shacl_validation?] == true,
      operations_migration_dry_run: contract.operations[:migration_dry_run?] == true,
      operations_rollback_plan: contract.operations[:rollback_plan?] == true,
      authority_select_construct_do: contract.authority[:select_construct_do_separated?] == true,
      authority_brce_required: contract.authority[:brce_required_for_do?] == true,
      topology_selected_candidate: contract.selected_topology in contract.topology_candidates
    }

    failed(checks)
  end

  defp failed_runtime_checks(contract) do
    checks = %{
      runtime_exact_subject_observed: contract.evidence[:exact_subject_runtime_observed?] == true,
      runtime_1m_concurrency_observed: contract.evidence[:stress_1m_concurrency_observed?] == true,
      runtime_exact_head_ci: present?(contract.evidence[:exact_head_ci_sha256]),
      runtime_obda_crown: present?(contract.evidence[:obda_crown_receipt_sha256]),
      authority_cutover_receipt: present?(contract.authority[:cutover_authority_receipt_sha256])
    }

    failed(checks)
  end

  defp build_receipt(contract, hard_failures, runtime_failures) do
    production_ready? = hard_failures == [] and runtime_failures == []
    blocked = hard_failures ++ runtime_failures
    status = cond do
      hard_failures != [] -> :BLOCKED
      production_ready? -> :ALIVE
      true -> :PARTIAL_ALIVE
    end

    standing = cond do
      hard_failures != [] -> :production_contract_refused
      production_ready? -> :fortune5_production_ready
      true -> :fortune5_contract_admitted_pending_runtime_evidence
    end

    receipt = %Receipt{
      status: status,
      standing: standing,
      contract_sha256: sha256(contract),
      production_ready?: production_ready?,
      admitted_checks: (@hard_checks ++ @runtime_checks) -- blocked,
      blocked_checks: blocked,
      topology_candidates: contract.topology_candidates,
      selected_topology: contract.selected_topology,
      refusals: Enum.map(hard_failures, &refusal(:REFUSED_FORTUNE5_PRODUCTION_BOUND, &1, "hard production invariant failed", %{}))
    }

    %{receipt | receipt_sha256: sha256(Map.from_struct(receipt))}
  end

  defp failed(checks) do
    checks
    |> Enum.reject(fn {_key, passed?} -> passed? end)
    |> Enum.map(&elem(&1, 0))
  end

  defp refusal(code, subject, detail, evidence), do: %Refusal{code: code, subject: subject, detail: detail, evidence: evidence}

  defp present?(value), do: is_binary(value) and value != ""

  defp atomize_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), atomize_value(value)}
      {key, value} -> {key, atomize_value(value)}
    end)
  end

  defp atomize_value(value) when is_map(value), do: atomize_keys(value)
  defp atomize_value(value), do: value

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value), do: deep_merge(left_value, right_value), else: right_value
    end)
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {canonical(key), canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key, [:deterministic]) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(other), do: other
end
