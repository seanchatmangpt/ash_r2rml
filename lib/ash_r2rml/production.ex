# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Production do
  @moduledoc """
  Evidence-bounded production quality admission for AshR2RML.

  Production is a quality and operational boundary, not an application domain.
  The module separates three independent questions:

  * is a design candidate lawful and reversible?
  * has the exact subject accumulated the required technical evidence?
  * has an external authority admitted a specific DO operation?

  Technical production standing never manufactures cutover authority.
  """

  alias AshR2RML.DfCM

  defmodule Profile do
    @moduledoc "Versionable production quality requirements."
    defstruct [
      :id,
      :design_space,
      objectives: %{},
      availability: %{},
      security: %{},
      reproducibility: %{},
      dependency_policy: %{},
      required_capabilities: [],
      required_evidence: []
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Evidence do
    @moduledoc "Observed evidence bound to an exact subject and environment."
    @enforce_keys [:kind, :status, :subject_sha256, :receipt_sha256]
    defstruct [
      :kind,
      :status,
      :subject_sha256,
      :receipt_sha256,
      :environment_sha256,
      :observed_at,
      metrics: %{},
      metadata: %{}
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Refusal do
    @moduledoc "Typed production admission refusal."
    @enforce_keys [:code, :subject, :detail]
    defstruct [:code, :subject, :detail, evidence: %{}]

    @type t :: %__MODULE__{}
  end

  defmodule Admission do
    @moduledoc "Technical production standing for one exact subject."
    defstruct [
      :status,
      :standing,
      :profile_sha256,
      :subject_sha256,
      :receipt_sha256,
      verified: [],
      missing: [],
      refused: [],
      observations: []
    ]

    @type t :: %__MODULE__{}
  end

  defmodule DoReceipt do
    @moduledoc "BRCE-bound admission for one explicit irreversible operation."
    defstruct [
      :subject_sha256,
      :production_receipt_sha256,
      :authority_sha256,
      :pre_state_sha256,
      :post_state_sha256,
      :replay_plan_sha256,
      :brce_receipt_sha256,
      :receipt_sha256
    ]

    @type t :: %__MODULE__{}
  end

  @required_evidence [
    :exact_head_compile,
    :unit_and_integration_suite,
    :rdf_parser_round_trip,
    :ggen_two_pass_determinism,
    :obda_behavioral_crown,
    :million_concurrency_load,
    :multi_zone_failover,
    :disaster_recovery_replay,
    :dependency_security_audit,
    :sbom_and_provenance,
    :release_rollback_drill
  ]

  @required_capabilities [
    :semantic_admission,
    :canonical_mapping_ir,
    :r2rml_projection,
    :shacl_projection,
    :ggen_manufacturing,
    :deterministic_replay,
    :bounded_execution,
    :tenant_isolation,
    :observability,
    :supply_chain_integrity,
    :disaster_recovery,
    :brce_authority_boundary
  ]

  @spec default_profile() :: Profile.t()
  def default_profile do
    %Profile{
      id: :ash_r2rml_production_v1,
      design_space: design_space(),
      objectives: %{
        p99_cold_path_ms: 500,
        queue_budget_ms: 50,
        min_concurrent_operations: 1_000_000,
        availability_percent: 99.99,
        max_recovery_point_seconds: 60,
        max_recovery_time_seconds: 300
      },
      availability: %{
        min_regions: 2,
        min_zones_per_region: 3,
        horizontal_scaling: true,
        partitioned_execution: true,
        backpressure: true,
        failover_tested: true,
        disaster_recovery_tested: true
      },
      security: %{
        least_privilege: true,
        ambient_do_authority: false,
        tenant_default_deny: true,
        externalized_secrets: true,
        signed_artifacts: true,
        sbom_required: true,
        provenance_required: true
      },
      reproducibility: %{
        deterministic_compilation: true,
        deterministic_ggen_two_pass: true,
        exact_toolchain_identity: true,
        clean_dependency_build: true,
        replay_receipt_required: true
      },
      dependency_policy: %{
        known_critical_vulnerabilities: 0,
        known_high_vulnerabilities: 0,
        audit_receipt_required: true
      },
      required_capabilities: @required_capabilities,
      required_evidence: @required_evidence
    }
  end

  @spec design_space() :: DfCM.Space.t()
  def design_space do
    dimensions = [
      dimension(:deployment_topology, [:single_region, :active_passive, :active_active, :cellular], :active_passive),
      dimension(:tenancy_model, [:shared_schema, :schema_per_tenant, :database_per_tenant, :cell_per_tenant_class], :schema_per_tenant),
      dimension(:consistency_model, [:strong, :bounded_staleness, :eventual], :strong),
      dimension(:execution_mode, [:compile_only, :read_only_runtime, :receipted_write_runtime], :compile_only),
      dimension(:control_plane, [:centralized, :regional, :cellular], :regional),
      dimension(:partition_strategy, [:tenant_hash, :semantic_subject_hash, :region_tenant_hash], :region_tenant_hash),
      dimension(:release_strategy, [:rolling, :blue_green, :canary, :cell_progressive], :canary),
      dimension(:data_residency, [:global, :regional, :country_bound], :regional),
      dimension(:obda_topology, [:embedded, :sidecar, :service, :pool], :pool),
      dimension(:secret_delivery, [:external_manager, :workload_identity], :workload_identity),
      dimension(:observability, [:otel, :otel_plus_ocel], :otel_plus_ocel),
      dimension(:artifact_distribution, [:registry_digest, :airgap_bundle], :registry_digest),
      dimension(:migration_strategy, [:expand_contract, :shadow_dual_write, :offline], :expand_contract),
      dimension(:recovery_strategy, [:restart, :replay, :failover_replay], :failover_replay),
      dimension(:cache_strategy, [:none, :local, :distributed], :local),
      dimension(:runtime_isolation, [:beam_process, :supervised_port, :container, :sandbox], :supervised_port)
    ]

    constraints = [
      constraint(:cellular_requires_cellular_control, %{deployment_topology: :cellular}, %{control_plane: :cellular}),
      constraint(:cell_tenancy_requires_cellular_topology, %{tenancy_model: :cell_per_tenant_class}, %{deployment_topology: :cellular}),
      constraint(:cell_progressive_requires_cellular_topology, %{release_strategy: :cell_progressive}, %{deployment_topology: :cellular}),
      constraint(:active_active_rejects_centralized_control, %{deployment_topology: :active_active}, %{}, %{control_plane: :centralized}),
      constraint(:write_runtime_requires_replay, %{execution_mode: :receipted_write_runtime}, %{recovery_strategy: [:replay, :failover_replay]}),
      constraint(:dual_write_requires_receipted_write, %{migration_strategy: :shadow_dual_write}, %{execution_mode: :receipted_write_runtime})
    ]

    {:ok, space} = DfCM.new(dimensions, constraints, max_examined: 250_000, max_candidates: 10_000)
    space
  end

  @spec default_assignment() :: map()
  def default_assignment do
    design_space().dimensions
    |> Map.new(&{&1.id, &1.default})
  end

  @spec admit(Profile.t(), String.t(), [Evidence.t() | map()]) :: Admission.t()
  def admit(%Profile{} = profile, subject_sha256, evidence \\ []) when is_binary(subject_sha256) do
    structural_refusals = validate_profile(profile)
    normalized = Enum.map(evidence, &normalize_evidence/1)

    {verified, missing, evidence_refusals} =
      verify_evidence(profile.required_evidence, subject_sha256, normalized)

    refusals = structural_refusals ++ evidence_refusals

    status =
      cond do
        structural_refusals != [] -> :BLOCKED
        missing == [] and evidence_refusals == [] -> :ALIVE
        true -> :PARTIAL_ALIVE
      end

    base = %Admission{
      status: status,
      standing: standing(status),
      profile_sha256: sha256(profile),
      subject_sha256: subject_sha256,
      receipt_sha256: nil,
      verified: verified,
      missing: missing,
      refused: refusals,
      observations: Enum.map(normalized, &evidence_identity/1)
    }

    %{base | receipt_sha256: sha256(Map.from_struct(base))}
  end

  @spec operational_ready?(Admission.t()) :: boolean()
  def operational_ready?(%Admission{status: :ALIVE, missing: [], refused: []}), do: true
  def operational_ready?(_), do: false

  @spec authorize_do(Admission.t(), map()) :: {:ok, DoReceipt.t()} | {:error, Refusal.t()}
  def authorize_do(%Admission{} = admission, authority) when is_map(authority) do
    required = [
      :authority_sha256,
      :pre_state_sha256,
      :post_state_sha256,
      :replay_plan_sha256,
      :brce_receipt_sha256
    ]

    missing = Enum.reject(required, &(present?(fetch(authority, &1, nil))))

    cond do
      not operational_ready?(admission) ->
        {:error,
         refusal(
           :REFUSED_DO_WITHOUT_PRODUCTION_STANDING,
           admission.subject_sha256,
           "DO requires an ALIVE technical production admission"
         )}

      fetch(authority, :brce?, false) != true ->
        {:error,
         refusal(
           :REFUSED_DO_OUTSIDE_BRCE,
           admission.subject_sha256,
           "BRCE is the exclusive DO authority boundary"
         )}

      missing != [] ->
        {:error,
         refusal(
           :REFUSED_UNRECEIPTED_ACTUATION,
           admission.subject_sha256,
           "DO authority is missing required consequence/replay identities",
           %{missing: missing}
         )}

      true ->
        base = %DoReceipt{
          subject_sha256: admission.subject_sha256,
          production_receipt_sha256: admission.receipt_sha256,
          authority_sha256: fetch(authority, :authority_sha256, nil),
          pre_state_sha256: fetch(authority, :pre_state_sha256, nil),
          post_state_sha256: fetch(authority, :post_state_sha256, nil),
          replay_plan_sha256: fetch(authority, :replay_plan_sha256, nil),
          brce_receipt_sha256: fetch(authority, :brce_receipt_sha256, nil),
          receipt_sha256: nil
        }

        {:ok, %{base | receipt_sha256: sha256(Map.from_struct(base))}}
    end
  end

  @spec profile_sha256(Profile.t()) :: String.t()
  def profile_sha256(%Profile{} = profile), do: sha256(profile)

  defp dimension(id, options, default) do
    %DfCM.Dimension{id: id, options: options, default: default}
  end

  defp constraint(id, match, require, forbid \\ %{}) do
    %DfCM.Constraint{id: id, match: match, require: require, forbid: forbid}
  end

  defp validate_profile(%Profile{} = profile) do
    checks = [
      {profile.objectives.p99_cold_path_ms <= 500, :p99_cold_path_ms},
      {profile.objectives.min_concurrent_operations >= 1_000_000, :min_concurrent_operations},
      {profile.availability.min_regions >= 2, :min_regions},
      {profile.availability.min_zones_per_region >= 3, :min_zones_per_region},
      {profile.security.ambient_do_authority == false, :ambient_do_authority},
      {profile.security.least_privilege == true, :least_privilege},
      {profile.security.externalized_secrets == true, :externalized_secrets},
      {profile.reproducibility.deterministic_ggen_two_pass == true, :deterministic_ggen_two_pass},
      {profile.reproducibility.clean_dependency_build == true, :clean_dependency_build},
      {profile.dependency_policy.known_critical_vulnerabilities == 0, :critical_vulnerabilities},
      {profile.dependency_policy.known_high_vulnerabilities == 0, :high_vulnerabilities}
    ]

    checks
    |> Enum.reject(fn {ok?, _name} -> ok? end)
    |> Enum.map(fn {_ok?, name} ->
      refusal(
        :REFUSED_PRODUCTION_PROFILE_BOUND,
        name,
        "production profile violates a non-negotiable quality bound"
      )
    end)
  end

  defp verify_evidence(required, subject_sha256, evidence) do
    by_kind = Enum.group_by(evidence, & &1.kind)

    Enum.reduce(required, {[], [], []}, fn kind, {verified, missing, refusals} ->
      observations = Map.get(by_kind, kind, [])

      case Enum.find(observations, &valid_evidence?(&1, subject_sha256)) do
        nil ->
          subject_mismatches = Enum.filter(observations, &(&1.subject_sha256 != subject_sha256))

          if subject_mismatches == [] do
            {verified, [kind | missing], refusals}
          else
            refusal =
              refusal(
                :REFUSED_EVIDENCE_SUBJECT_MISMATCH,
                kind,
                "evidence exists but is bound to a different semantic subject",
                %{expected_subject_sha256: subject_sha256}
              )

            {verified, [kind | missing], [refusal | refusals]}
          end

        evidence_item ->
          {[{kind, evidence_item.receipt_sha256} | verified], missing, refusals}
      end
    end)
    |> then(fn {verified, missing, refusals} ->
      {Enum.sort(verified), Enum.sort(missing), Enum.reverse(refusals)}
    end)
  end

  defp valid_evidence?(%Evidence{} = evidence, subject_sha256) do
    evidence.status == :VERIFIED and
      evidence.subject_sha256 == subject_sha256 and
      present?(evidence.receipt_sha256)
  end

  defp normalize_evidence(%Evidence{} = evidence), do: evidence

  defp normalize_evidence(map) when is_map(map) do
    %Evidence{
      kind: fetch(map, :kind, :unknown),
      status: fetch(map, :status, :UNKNOWN),
      subject_sha256: fetch(map, :subject_sha256, ""),
      receipt_sha256: fetch(map, :receipt_sha256, ""),
      environment_sha256: fetch(map, :environment_sha256, nil),
      observed_at: fetch(map, :observed_at, nil),
      metrics: fetch(map, :metrics, %{}),
      metadata: fetch(map, :metadata, %{})
    }
  end

  defp evidence_identity(%Evidence{} = evidence) do
    %{
      kind: evidence.kind,
      status: evidence.status,
      subject_sha256: evidence.subject_sha256,
      receipt_sha256: evidence.receipt_sha256,
      environment_sha256: evidence.environment_sha256
    }
  end

  defp standing(:ALIVE), do: :technical_production_evidence_complete
  defp standing(:PARTIAL_ALIVE), do: :technical_production_evidence_incomplete
  defp standing(:BLOCKED), do: :production_profile_refused

  defp refusal(code, subject, detail, evidence \\ %{}) do
    %Refusal{code: code, subject: subject, detail: detail, evidence: evidence}
  end

  defp present?(value), do: is_binary(value) and byte_size(value) > 0

  defp fetch(map, key, default) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp sha256(term), do: DfCM.sha256(term)
end
