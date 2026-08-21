# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Production.Capabilities do
  @moduledoc """
  Dependency-closed production capability and evidence graph.

  A capability is a claim with a required proof class, not a feature flag.
  Closure preserves prerequisites and refuses unknown capability identifiers.
  """

  alias AshR2RML.DfCM

  defmodule Capability do
    @moduledoc "One capability with proof, authority and dependency requirements."
    @enforce_keys [:id, :category, :proof, :authority]
    defstruct [:id, :category, :proof, :authority, :criticality, :description, requires: []]

    @type t :: %__MODULE__{}
  end

  defmodule Observation do
    @moduledoc "Evidence for one capability."
    @enforce_keys [:capability, :status]
    defstruct [:capability, :status, :proof, :receipt_sha256, :subject_sha256, :environment_sha256]

    @type t :: %__MODULE__{}
  end

  defmodule Admission do
    @moduledoc "Evidence-bounded capability admission."
    defstruct [
      :status,
      :graph_sha256,
      :receipt_sha256,
      requested: [],
      closure: [],
      alive: [],
      partial_alive: [],
      unknown: [],
      refused: [],
      evidence_plan: []
    ]

    @type t :: %__MODULE__{}
  end

  @spec catalog() :: [Capability.t()]
  def catalog do
    [
      cap(:ontology_profile_ingestion, :semantic_core, :parser, :select, :critical),
      cap(:shacl_operational_closure, :semantic_core, :parser_and_falsifier, :select, :critical, [:ontology_profile_ingestion]),
      cap(:semantic_admission, :semantic_core, :unit_and_falsifier, :select, :critical, [:shacl_operational_closure]),
      cap(:canonical_semantic_ir, :semantic_core, :unit, :construct, :critical, [:semantic_admission]),
      cap(:canonical_mapping_ir, :semantic_core, :unit, :construct, :critical, [:canonical_semantic_ir]),
      cap(:semantic_identity_integrity, :semantic_core, :falsifier, :select, :critical, [:canonical_mapping_ir]),
      cap(:datatype_integrity, :semantic_core, :falsifier, :select, :critical, [:canonical_mapping_ir]),
      cap(:relationship_integrity, :semantic_core, :falsifier, :select, :critical, [:canonical_mapping_ir]),
      cap(:r2rml_projection, :semantic_projection, :rdf_parser, :construct, :critical, [:canonical_mapping_ir]),
      cap(:shacl_projection, :semantic_projection, :rdf_parser, :construct, :critical, [:canonical_mapping_ir]),
      cap(:ash_projection, :semantic_projection, :compile, :construct, :high, [:canonical_semantic_ir]),
      cap(:postgres_projection, :semantic_projection, :integration, :construct, :high, [:canonical_semantic_ir]),
      cap(:deterministic_compilation, :manufacturing, :two_pass, :construct, :critical, [:canonical_mapping_ir]),
      cap(:ggen_manufacturing, :manufacturing, :ggen_execution, :construct, :critical, [:deterministic_compilation, :r2rml_projection, :shacl_projection]),
      cap(:ggen_fail_closed_gates, :manufacturing, :ggen_execution, :construct, :critical, [:ggen_manufacturing]),
      cap(:ggen_two_pass_determinism, :manufacturing, :two_pass, :construct, :critical, [:ggen_fail_closed_gates]),
      cap(:staged_hash_verification, :manufacturing, :hash_witness, :construct, :high, [:ggen_two_pass_determinism]),
      cap(:sparql_admission, :query, :parser, :select, :critical, [:canonical_mapping_ir]),
      cap(:bounded_execution, :query, :runtime_observation, :runtime, :critical, [:sparql_admission]),
      cap(:obda_protocol, :query, :real_engine, :runtime, :critical, [:bounded_execution, :r2rml_projection]),
      cap(:obda_behavioral_parity, :query, :paired_observation, :runtime, :critical, [:obda_protocol]),
      cap(:deterministic_replay, :operations, :replay, :runtime, :critical, [:deterministic_compilation]),
      cap(:otp_fault_isolation, :operations, :chaos, :runtime, :high, [:bounded_execution]),
      cap(:backpressure, :operations, :load, :runtime, :critical, [:bounded_execution]),
      cap(:horizontal_scale, :operations, :load, :runtime, :critical, [:backpressure]),
      cap(:million_concurrency_target, :operations, :load, :runtime, :critical, [:horizontal_scale]),
      cap(:multi_zone_failover, :resilience, :chaos, :runtime, :critical, [:otp_fault_isolation]),
      cap(:multi_region_failover, :resilience, :chaos, :runtime, :critical, [:multi_zone_failover]),
      cap(:disaster_recovery, :resilience, :dr_drill, :runtime, :critical, [:multi_region_failover, :deterministic_replay]),
      cap(:tenant_context, :security, :falsifier, :runtime, :critical, [:canonical_mapping_ir]),
      cap(:tenant_isolation, :security, :adversarial, :runtime, :critical, [:tenant_context]),
      cap(:residency_routing, :security, :adversarial, :runtime, :high, [:tenant_context]),
      cap(:least_privilege, :security, :policy_review, :construct, :critical),
      cap(:external_secret_delivery, :security, :integration, :runtime, :critical, [:least_privilege]),
      cap(:brce_authority_boundary, :authority, :falsifier, :do, :critical, [:least_privilege]),
      cap(:observability, :observability, :runtime_observation, :runtime, :critical, [:canonical_mapping_ir]),
      cap(:trace_receipt_correlation, :observability, :runtime_observation, :runtime, :high, [:observability]),
      cap(:bounded_telemetry_cardinality, :observability, :falsifier, :runtime, :high, [:observability]),
      cap(:semantic_audit_log, :observability, :runtime_observation, :runtime, :critical, [:trace_receipt_correlation]),
      cap(:sbom, :supply_chain, :artifact, :construct, :critical),
      cap(:artifact_signature, :supply_chain, :signature, :construct, :critical, [:sbom]),
      cap(:provenance_attestation, :supply_chain, :attestation, :construct, :critical, [:artifact_signature]),
      cap(:dependency_security_audit, :supply_chain, :security_audit, :construct, :critical, [:sbom]),
      cap(:supply_chain_integrity, :supply_chain, :attestation, :construct, :critical, [:provenance_attestation, :dependency_security_audit]),
      cap(:progressive_delivery, :release, :runtime_observation, :runtime, :high, [:observability]),
      cap(:rollback_drill, :release, :replay, :runtime, :critical, [:progressive_delivery, :deterministic_replay]),
      cap(:migration_dry_run, :release, :integration, :construct, :critical, [:postgres_projection]),
      cap(:schema_semantic_drift_detection, :release, :falsifier, :select, :critical, [:canonical_semantic_ir, :migration_dry_run])
    ]
  end

  @spec graph_sha256() :: String.t()
  def graph_sha256, do: DfCM.sha256(catalog())

  @spec closure([atom()]) :: {:ok, [atom()]} | {:error, [atom()]}
  def closure(requested) when is_list(requested) do
    by_id = Map.new(catalog(), &{&1.id, &1})
    unknown = Enum.uniq(requested) -- Map.keys(by_id)

    if unknown == [] do
      {:ok, expand(Enum.uniq(requested), by_id, MapSet.new()) |> MapSet.to_list() |> Enum.sort()}
    else
      {:error, Enum.sort(unknown)}
    end
  end

  @spec admit([atom()], [Observation.t() | map()]) :: Admission.t()
  def admit(requested, observations \\ []) do
    normalized = Enum.map(observations, &normalize_observation/1)
    by_capability = Enum.group_by(normalized, & &1.capability)
    by_id = Map.new(catalog(), &{&1.id, &1})

    case closure(requested) do
      {:error, unknown} ->
        base = %Admission{
          status: :REFUSED,
          graph_sha256: graph_sha256(),
          requested: Enum.sort(Enum.uniq(requested)),
          unknown: unknown,
          refused: Enum.map(unknown, &{:REFUSED_UNKNOWN_CAPABILITY, &1}),
          receipt_sha256: nil
        }

        %{base | receipt_sha256: DfCM.sha256(Map.from_struct(base))}

      {:ok, closed} ->
        classified =
          Enum.map(closed, fn id ->
            capability = Map.fetch!(by_id, id)
            observations_for_capability = Map.get(by_capability, id, [])
            {id, classify(capability, observations_for_capability)}
          end)

        alive = for {id, :ALIVE} <- classified, do: id
        partial = for {id, :PARTIAL_ALIVE} <- classified, do: id
        unknown = for {id, :UNKNOWN} <- classified, do: id

        status = if unknown == [] and partial == [], do: :ALIVE, else: :PARTIAL_ALIVE

        base = %Admission{
          status: status,
          graph_sha256: graph_sha256(),
          requested: Enum.sort(Enum.uniq(requested)),
          closure: closed,
          alive: alive,
          partial_alive: partial,
          unknown: unknown,
          refused: [],
          evidence_plan: evidence_plan(classified, by_id),
          receipt_sha256: nil
        }

        %{base | receipt_sha256: DfCM.sha256(Map.from_struct(base))}
    end
  end

  defp classify(capability, observations) do
    cond do
      Enum.any?(observations, &valid_observation?(&1, capability)) -> :ALIVE
      observations != [] -> :PARTIAL_ALIVE
      true -> :UNKNOWN
    end
  end

  defp valid_observation?(observation, capability) do
    observation.status == :VERIFIED and
      observation.proof == capability.proof and
      is_binary(observation.receipt_sha256) and
      byte_size(observation.receipt_sha256) > 0
  end

  defp evidence_plan(classified, by_id) do
    classified
    |> Enum.reject(fn {_id, status} -> status == :ALIVE end)
    |> Enum.map(fn {id, status} ->
      capability = Map.fetch!(by_id, id)
      %{capability: id, current_status: status, required_proof: capability.proof, authority: capability.authority}
    end)
  end

  defp expand([], _by_id, seen), do: seen

  defp expand([id | rest], by_id, seen) do
    if MapSet.member?(seen, id) do
      expand(rest, by_id, seen)
    else
      capability = Map.fetch!(by_id, id)
      expand(capability.requires ++ rest, by_id, MapSet.put(seen, id))
    end
  end

  defp normalize_observation(%Observation{} = observation), do: observation

  defp normalize_observation(map) when is_map(map) do
    %Observation{
      capability: fetch(map, :capability, :unknown),
      status: fetch(map, :status, :UNKNOWN),
      proof: fetch(map, :proof, nil),
      receipt_sha256: fetch(map, :receipt_sha256, nil),
      subject_sha256: fetch(map, :subject_sha256, nil),
      environment_sha256: fetch(map, :environment_sha256, nil)
    }
  end

  defp cap(id, category, proof, authority, criticality, requires \\ []) do
    %Capability{
      id: id,
      category: category,
      proof: proof,
      authority: authority,
      criticality: criticality,
      requires: requires
    }
  end

  defp fetch(map, key, default), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
