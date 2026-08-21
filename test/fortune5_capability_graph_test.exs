# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.CapabilityGraphTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.CapabilityGraph
  alias AshR2RML.Fortune5.CapabilityGraph.Observation

  test "catalog is dependency closed and broad across production domains" do
    assert :ok = CapabilityGraph.validate_catalog()

    catalog = CapabilityGraph.catalog()
    domains = catalog |> Enum.map(& &1.domain) |> Enum.uniq()

    assert length(catalog) >= 70
    assert :semantic_core in domains
    assert :ggen in domains
    assert :obda in domains
    assert :scale in domains
    assert :tenancy in domains
    assert :resilience in domains
    assert :observability in domains
    assert :security in domains
    assert :supply_chain in domains
    assert :governance in domains
    assert :compliance in domains
    assert :operations in domains
  end

  test "closure preserves prerequisites before dependent capability" do
    assert {:ok, closure} = CapabilityGraph.closure(:release_receipt)

    assert :sbom in closure
    assert :signed_artifacts in closure
    assert :provenance_attestation in closure
    assert :vulnerability_gate in closure
    assert :progressive_delivery in closure
    assert :rollback_plan in closure
    assert :release_receipt in closure

    assert Enum.find_index(closure, &(&1 == :sbom)) < Enum.find_index(closure, &(&1 == :signed_artifacts))
    assert Enum.find_index(closure, &(&1 == :rollback_plan)) < Enum.find_index(closure, &(&1 == :release_receipt))
  end

  test "unknown capability is not admitted" do
    assert {:error, refusal} = CapabilityGraph.closure(:made_up_capability)
    assert refusal.code == :UNKNOWN_CAPABILITY
  end

  test "source presence without observations remains partial alive" do
    admission = CapabilityGraph.admit([:ggen_replay_receipt, :sql_sparql_parity], [])

    assert admission.status == :PARTIAL_ALIVE
    assert admission.alive == []
    assert admission.unknown != []
    assert admission.evidence_plan != []
    assert String.length(admission.graph_sha256) == 64
    assert String.length(admission.receipt_sha256) == 64
  end

  test "ALIVE requires exact proof class and stable receipt for entire closure" do
    assert {:ok, closure} = CapabilityGraph.closure(:ggen_replay_receipt)

    by_id = Map.new(CapabilityGraph.catalog(), &{&1.id, &1})

    observations =
      Enum.map(closure, fn id ->
        capability = Map.fetch!(by_id, id)

        %Observation{
          capability: id,
          status: :ALIVE,
          proof: capability.proof,
          receipt_sha256: receipt_for(id),
          subject_sha256: String.duplicate("a", 64),
          environment_sha256: String.duplicate("b", 64)
        }
      end)

    admission = CapabilityGraph.admit(:ggen_replay_receipt, observations)

    assert admission.status == :ALIVE
    assert admission.unknown == []
    assert admission.partial_alive == []
    assert admission.blocked == []
    assert admission.alive == closure
    assert admission.evidence_plan == []
  end

  test "wrong proof class cannot promote an observed capability to ALIVE" do
    observation = %Observation{
      capability: :ontology_profile_ingestion,
      status: :ALIVE,
      proof: :documentation,
      receipt_sha256: String.duplicate("c", 64)
    }

    admission = CapabilityGraph.admit(:ontology_profile_ingestion, [observation])
    assert admission.status == :PARTIAL_ALIVE
    assert admission.partial_alive == [:ontology_profile_ingestion]
    assert admission.alive == []
  end

  test "blocked and unsupported evidence remain distinct" do
    blocked = %Observation{
      capability: :ontology_profile_ingestion,
      status: :BLOCKED,
      proof: :unit_and_parser,
      receipt_sha256: String.duplicate("d", 64)
    }

    unsupported = %Observation{
      capability: :ontology_profile_ingestion,
      status: :UNSUPPORTED,
      proof: :unit_and_parser,
      receipt_sha256: String.duplicate("e", 64)
    }

    blocked_admission = CapabilityGraph.admit(:ontology_profile_ingestion, [blocked])
    unsupported_admission = CapabilityGraph.admit(:ontology_profile_ingestion, [unsupported])

    assert blocked_admission.status == :BLOCKED
    assert blocked_admission.blocked == [:ontology_profile_ingestion]

    assert unsupported_admission.status == :UNSUPPORTED
    assert unsupported_admission.unsupported == [:ontology_profile_ingestion]
  end

  test "domain matrix is stable and exposes proof plus authority" do
    first = CapabilityGraph.domain_matrix()
    second = CapabilityGraph.domain_matrix()

    assert first == second
    assert first.security != []
    assert Enum.any?(first.security, &(&1.id == :brce_do_authority and &1.authority == :do))
  end

  defp receipt_for(id) do
    :crypto.hash(:sha256, Atom.to_string(id))
    |> Base.encode16(case: :lower)
  end
end
