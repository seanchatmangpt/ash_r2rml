# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ProductionCapabilitiesTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Production.Capabilities

  test "capability closure recursively includes prerequisites" do
    assert {:ok, closure} = Capabilities.closure([:supply_chain_integrity])

    assert :supply_chain_integrity in closure
    assert :provenance_attestation in closure
    assert :artifact_signature in closure
    assert :sbom in closure
    assert :dependency_security_audit in closure
  end

  test "unknown capability is a typed refusal" do
    admission = Capabilities.admit([:definitely_not_a_capability])

    assert admission.status == :REFUSED
    assert admission.unknown == [:definitely_not_a_capability]
    assert {:REFUSED_UNKNOWN_CAPABILITY, :definitely_not_a_capability} in admission.refused
  end

  test "proof class and receipt identity are required for ALIVE" do
    capability = Enum.find(Capabilities.catalog(), &(&1.id == :sbom))

    wrong =
      Capabilities.admit([:sbom], [
        %Capabilities.Observation{
          capability: :sbom,
          status: :VERIFIED,
          proof: :unit,
          receipt_sha256: String.duplicate("a", 64)
        }
      ])

    assert wrong.partial_alive == [:sbom]

    correct =
      Capabilities.admit([:sbom], [
        %Capabilities.Observation{
          capability: :sbom,
          status: :VERIFIED,
          proof: capability.proof,
          receipt_sha256: String.duplicate("a", 64)
        }
      ])

    assert correct.status == :ALIVE
    assert correct.alive == [:sbom]
  end

  test "graph identity is deterministic" do
    assert Capabilities.graph_sha256() == Capabilities.graph_sha256()
    assert byte_size(Capabilities.graph_sha256()) == 64
  end
end
