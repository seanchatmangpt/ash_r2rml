# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5ProductionClosureTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.ProductionClosure

  test "default Fortune-5 contract is admitted but not crowned without runtime evidence" do
    assert {:ok, receipt} = ProductionClosure.admit()

    assert receipt.status == :PARTIAL_ALIVE
    assert receipt.standing == :fortune5_contract_admitted_pending_runtime_evidence
    refute receipt.production_ready?
    assert :runtime_exact_subject_observed in receipt.blocked_checks
    assert :authority_cutover_receipt in receipt.blocked_checks
    assert receipt.selected_topology == :multi_region_active_passive
    assert :cellular_multi_region in receipt.topology_candidates
  end

  test "runtime and cutover evidence promotes the same contract to ALIVE" do
    contract = %{
      evidence: %{
        exact_subject_runtime_observed?: true,
        stress_1m_concurrency_observed?: true,
        exact_head_ci_sha256: "ci-receipt",
        obda_crown_receipt_sha256: "obda-crown"
      },
      authority: %{cutover_authority_receipt_sha256: "operator-cutover"}
    }

    assert {:ok, receipt} = ProductionClosure.admit(contract)
    assert receipt.status == :ALIVE
    assert receipt.standing == :fortune5_production_ready
    assert receipt.production_ready?
    assert receipt.blocked_checks == []
    assert ProductionClosure.production_ready?(contract)
  end

  test "SLO and concurrency claims fail closed instead of becoming production-ready" do
    contract = %{
      slo: %{p99_cold_path_ms: 750},
      capacity: %{min_concurrent_operations: 999_999}
    }

    assert {:error, receipt} = ProductionClosure.admit(contract)
    assert receipt.status == :BLOCKED
    assert :slo_p99_cold_path in receipt.blocked_checks
    assert :capacity_concurrency in receipt.blocked_checks
    assert Enum.any?(receipt.refusals, &(&1.code == :REFUSED_FORTUNE5_PRODUCTION_BOUND))
  end

  test "selected topology must remain one of the preserved DfCM candidates" do
    contract = %{
      topology_candidates: [:multi_region_active_passive],
      selected_topology: :unbounded_magic_cloud
    }

    assert {:error, receipt} = ProductionClosure.admit(contract)
    assert :topology_selected_candidate in receipt.blocked_checks
  end

  test "BRCE is the exclusive DO admission path" do
    assert {:error, refusal} = ProductionClosure.authorize_do(%{})
    assert refusal.code == :REFUSED_UNRECEIPTED_ACTUATION
    assert :brce_receipt_sha256 in refusal.evidence.missing

    request = %{
      brce_receipt_sha256: "brce",
      authority_sha256: "authority",
      pre_state_sha256: "before",
      post_state_sha256: "after",
      replay_plan_sha256: "replay"
    }

    assert {:ok, do_receipt} = ProductionClosure.authorize_do(request)
    assert do_receipt.status == :PARTIAL_ALIVE
    assert do_receipt.standing == :brce_do_admitted
    assert do_receipt.replay_required?
  end

  test "receipts are deterministic and sensitive to admitted evidence" do
    assert {:ok, first} = ProductionClosure.admit()
    assert {:ok, replay} = ProductionClosure.admit()

    assert first.receipt_sha256 == replay.receipt_sha256
    assert first.contract_sha256 == replay.contract_sha256

    assert {:ok, changed} =
             ProductionClosure.admit(%{evidence: %{exact_head_ci_sha256: "different-ci"}})

    refute first.receipt_sha256 == changed.receipt_sha256
    refute first.contract_sha256 == changed.contract_sha256
  end
end
