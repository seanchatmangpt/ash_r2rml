# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.DfCM do
  @moduledoc """
  Bounded Design for Combinatorial Maximalism calculus for Fortune-5 deployment.

  The graph preserves the maximal reversible set of lawful configurations before
  an irreversible operational selection.  It is deliberately pure and does not
  actuate infrastructure.  A configuration is only a candidate until all hard
  constraints are admitted and an external authority selects it.

  The implementation uses a lazy Cartesian product so the logical design space
  may be very large without allocating the entire product.  Consumers must bound
  enumeration with `:max_candidates`, `:max_examined`, and optional selections.
  """

  defmodule Dimension do
    @moduledoc "One reversible design dimension in the Fortune-5 possibility graph."
    @enforce_keys [:id, :options]
    defstruct [:id, :description, :authority, options: [], default: nil, metadata: %{}]
  end

  defmodule Constraint do
    @moduledoc "Named admission rule. Rules are data, never anonymous executable authority."
    @enforce_keys [:id, :severity]
    defstruct [:id, :severity, :description, :falsifier]
  end

  defmodule Candidate do
    @moduledoc "One fully assigned configuration candidate."
    @enforce_keys [:id, :assignment]
    defstruct [
      :id,
      :assignment,
      :status,
      :standing,
      :score,
      :reversible?,
      :selected?,
      refusals: [],
      warnings: [],
      consequences: [],
      required_evidence: [],
      irreversible_edges: []
    ]
  end

  defmodule Graph do
    @moduledoc "Canonical bounded DfCM design graph."
    defstruct version: "fortune5-dfcm-v2",
              dimensions: [],
              constraints: [],
              bounds: %{max_candidates: 10_000, max_examined: 1_000_000},
              metadata: %{}
  end

  defmodule EnumerationReceipt do
    @moduledoc "Deterministic receipt for a bounded exploration pass."
    defstruct [
      :graph_sha256,
      :selection_sha256,
      :receipt_sha256,
      :status,
      :standing,
      :examined,
      :admitted,
      :refused,
      :returned,
      :truncated?,
      selected: %{},
      candidate_ids: [],
      refusal_histogram: %{}
    ]
  end

  @type assignment :: %{optional(atom()) => atom()}

  @doc "Return the canonical Fortune-5 design graph."
  @spec default_graph() :: Graph.t()
  def default_graph do
    %Graph{
      dimensions: dimensions(),
      constraints: constraints(),
      metadata: %{
        doctrine: :design_for_combinatorial_maximalism,
        authority_model: :select_construct_do,
        do_path: :brce,
        generated_projection_authority: :ggen,
        semantic_authority: :admitted_semantic_ir
      }
    }
  end

  @doc "Canonical dimension inventory."
  def dimensions do
    [
      dim(:deployment_topology,
        [:single_region, :multi_region_active_passive, :multi_region_active_active, :cellular_multi_region],
        "physical deployment topology",
        :platform_architecture,
        :multi_region_active_passive
      ),
      dim(:tenancy_model,
        [:shared_schema, :schema_per_tenant, :database_per_tenant, :cell_per_tenant_class],
        "tenant isolation topology",
        :data_governance,
        :shared_schema
      ),
      dim(:consistency_model,
        [:eventual, :read_after_write, :strong],
        "cross-node semantic consistency target",
        :data_architecture,
        :read_after_write
      ),
      dim(:execution_mode,
        [:compile_only, :read_only_runtime, :receipted_write_runtime],
        "maximum runtime authority exposed by the deployment",
        :security_authority,
        :read_only_runtime
      ),
      dim(:obda_topology,
        [:ontop_cli, :ontop_protocol, :external_protocol, :dual_engine_differential],
        "virtual RDF execution topology",
        :semantic_platform,
        :ontop_protocol
      ),
      dim(:partition_strategy,
        [:none, :tenant_hash, :semantic_class, :geography, :hybrid],
        "horizontal partition key family",
        :data_architecture,
        :tenant_hash
      ),
      dim(:availability_model,
        [:zonal, :regional, :multi_region],
        "failure-domain availability target",
        :sre,
        :multi_region
      ),
      dim(:disaster_recovery,
        [:backup_restore, :warm_standby, :hot_standby, :active_active],
        "disaster-recovery posture",
        :sre,
        :hot_standby
      ),
      dim(:observability,
        [:telemetry, :open_telemetry, :open_telemetry_receipts],
        "trace/metric/receipt correlation surface",
        :observability,
        :open_telemetry_receipts
      ),
      dim(:workload_identity,
        [:workload_identity, :spiffe, :oidc_federated],
        "machine identity source",
        :security,
        :spiffe
      ),
      dim(:secret_provider,
        [:external_env, :vault, :cloud_kms, :external_secrets_operator],
        "secret materialization provider",
        :security,
        :external_secrets_operator
      ),
      dim(:release_strategy,
        [:rolling, :blue_green, :canary, :cell_progressive],
        "release rollout strategy",
        :release_engineering,
        :canary
      ),
      dim(:migration_strategy,
        [:offline, :expand_contract, :shadow_dual_read, :shadow_dual_write],
        "schema/semantic migration strategy",
        :data_architecture,
        :expand_contract
      ),
      dim(:network_boundary,
        [:private_service, :zero_trust_mesh, :air_gapped],
        "network trust boundary",
        :security,
        :zero_trust_mesh
      ),
      dim(:data_residency,
        [:unrestricted, :country_pinned, :region_pinned, :sovereign_cell],
        "residency constraint class",
        :data_governance,
        :region_pinned
      ),
      dim(:compliance_profile,
        [:baseline, :soc2, :pci, :hipaa, :sox, :fedramp_high],
        "control profile to which evidence must be bound",
        :governance,
        :baseline
      ),
      dim(:cache_strategy,
        [:none, :local, :distributed, :semantic_materialization],
        "derived semantic cache topology",
        :performance,
        :local
      ),
      dim(:runtime_isolation,
        [:shared_pool, :tenant_pool, :cell_pool, :dedicated_workload],
        "runtime fault-containment boundary",
        :platform_architecture,
        :cell_pool
      ),
      dim(:artifact_distribution,
        [:single_registry, :replicated_registry, :sovereign_registry, :offline_bundle],
        "signed artifact distribution topology",
        :release_engineering,
        :replicated_registry
      ),
      dim(:control_plane,
        [:centralized, :regional_federated, :cellular_federated],
        "operator/control-plane topology",
        :platform_architecture,
        :regional_federated
      )
    ]
  end

  @doc "Hard and advisory cross-dimensional constraints."
  def constraints do
    [
      rule(:active_active_requires_strong_or_idempotent, :hard,
        "multi-region active/active must use strong consistency or a receipted idempotent write path"
      ),
      rule(:cellular_requires_partitioning, :hard,
        "cellular deployment requires an explicit partitioning strategy"
      ),
      rule(:database_per_tenant_requires_isolated_pool, :hard,
        "database-per-tenant requires tenant/cell/dedicated runtime isolation"
      ),
      rule(:sovereign_residency_requires_sovereign_distribution, :hard,
        "sovereign cells require sovereign or offline artifact distribution"
      ),
      rule(:air_gap_requires_offline_distribution, :hard,
        "air-gapped runtime cannot depend on a network artifact registry"
      ),
      rule(:air_gap_forbids_external_protocol, :hard,
        "air-gapped deployments cannot depend on an ambient external SPARQL protocol endpoint"
      ),
      rule(:write_runtime_requires_receipted_observability, :hard,
        "receipted write runtime requires trace-to-receipt correlation"
      ),
      rule(:write_runtime_requires_safe_migration, :hard,
        "receipted write runtime cannot use offline-only migration as its production strategy"
      ),
      rule(:active_active_dr_requires_multi_region, :hard,
        "active/active DR requires a multi-region deployment"
      ),
      rule(:multi_region_availability_requires_multi_region_deployment, :hard,
        "multi-region availability requires a multi-region or cellular deployment"
      ),
      rule(:strong_consistency_requires_nonlocal_coordination, :hard,
        "strong consistency with a multi-region deployment requires explicit coordination-capable topology"
      ),
      rule(:fedramp_high_requires_airgap_or_zero_trust, :hard,
        "FedRAMP High candidate must use zero-trust mesh or air-gapped network boundaries"
      ),
      rule(:regulated_requires_signed_distribution, :hard,
        "regulated profiles require replicated, sovereign, or offline signed distribution"
      ),
      rule(:pci_forbids_shared_pool, :hard,
        "PCI candidate must not use a fully shared runtime pool"
      ),
      rule(:hipaa_forbids_unrestricted_residency, :hard,
        "HIPAA candidate requires an explicit residency policy"
      ),
      rule(:dual_engine_requires_read_capability, :hard,
        "differential OBDA execution requires at least read-only runtime authority"
      ),
      rule(:semantic_materialization_requires_read_runtime, :hard,
        "semantic materialization cache is meaningless for compile-only runtime"
      ),
      rule(:shadow_dual_write_requires_receipted_write, :hard,
        "shadow dual-write migration requires the receipted write runtime"
      ),
      rule(:cell_progressive_requires_cellular, :hard,
        "cell-progressive release requires cellular deployment"
      ),
      rule(:cellular_control_plane_requires_cellular_deployment, :hard,
        "cellular-federated control plane requires cellular deployment"
      ),
      rule(:offline_bundle_prefers_airgap, :advisory,
        "offline artifact bundles are normally selected for air-gapped or sovereign deployments"
      ),
      rule(:single_region_limits_dr, :advisory,
        "single-region topology materially limits high-availability DR standing"
      ),
      rule(:shared_schema_limits_regulated_isolation, :advisory,
        "shared schema increases evidence burden for regulated tenant isolation"
      )
    ]
  end

  @doc "Lazily enumerate bounded lawful candidates."
  def enumerate(graph \\ default_graph(), opts \\ []) do
    selection = normalize_selection(Keyword.get(opts, :select, %{}))
    max_candidates = Keyword.get(opts, :max_candidates, graph.bounds.max_candidates)
    max_examined = Keyword.get(opts, :max_examined, graph.bounds.max_examined)
    include_refused? = Keyword.get(opts, :include_refused?, false)

    constrained_dimensions = apply_selection(graph.dimensions, selection)

    stream =
      constrained_dimensions
      |> assignments(%{})
      |> Stream.map(&evaluate(graph, &1))
      |> Stream.take(max_examined)

    candidates =
      stream
      |> Stream.filter(fn candidate -> include_refused? or candidate.refusals == [] end)
      |> Enum.take(max_candidates)

    receipt = enumeration_receipt(graph, selection, candidates, max_candidates, max_examined)
    {:ok, candidates, receipt}
  end

  @doc "Evaluate one fully-assigned candidate against all graph constraints."
  def evaluate(%Graph{} = graph, assignment) when is_map(assignment) do
    assignment = normalize_selection(assignment)

    missing =
      graph.dimensions
      |> Enum.map(& &1.id)
      |> Enum.reject(&Map.has_key?(assignment, &1))

    invalid =
      Enum.flat_map(graph.dimensions, fn dim ->
        case Map.fetch(assignment, dim.id) do
          {:ok, value} when value in dim.options -> []
          {:ok, value} -> [{:invalid_option, dim.id, value, dim.options}]
          :error -> []
        end
      end)

    base_refusals =
      Enum.map(missing, &{:REFUSED_INCOMPLETE_CANDIDATE, &1}) ++
        Enum.map(invalid, fn {:invalid_option, id, value, options} ->
          {:REFUSED_INVALID_DFCM_OPTION, id, value, options}
        end)

    {hard, warnings} =
      Enum.reduce(graph.constraints, {[], []}, fn constraint, {hard, warnings} ->
        case check(constraint.id, assignment) do
          :ok -> {hard, warnings}
          {:refused, evidence} when constraint.severity == :hard ->
            {[refusal(constraint, evidence) | hard], warnings}

          {:refused, evidence} ->
            {hard, [warning(constraint, evidence) | warnings]}
        end
      end)

    refusals = Enum.reverse(base_refusals ++ hard)
    warnings = Enum.reverse(warnings)
    consequences = consequences(assignment)
    irreversible = irreversible_edges(assignment)
    reversible? = irreversible == []

    %Candidate{
      id: sha256(assignment),
      assignment: assignment,
      status: if(refusals == [], do: :ADMITTED, else: :REFUSED),
      standing: if(refusals == [], do: :candidate_constructible, else: :candidate_rejected),
      score: score(assignment, warnings, irreversible),
      reversible?: reversible?,
      selected?: false,
      refusals: refusals,
      warnings: warnings,
      consequences: consequences,
      required_evidence: required_evidence(assignment),
      irreversible_edges: irreversible
    }
  end

  @doc "Select one admitted candidate with explicit external authority."
  def select(%Candidate{refusals: []} = candidate, authority) when is_map(authority) do
    authority_id = value(authority, :receipt_sha256)
    authorized? = value(authority, :authorized?) == true

    if authorized? and present?(authority_id) do
      {:ok,
       %{
         candidate
         | selected?: true,
           standing: :selected_for_construct,
           consequences:
             [{:selection_authority, authority_id} | candidate.consequences]
       }}
    else
      {:error,
       %{
         code: :REFUSED_DFCM_SELECTION_WITHOUT_AUTHORITY,
         subject: candidate.id,
         detail: "selection requires authorized?: true and stable receipt_sha256",
         evidence: authority
       }}
    end
  end

  def select(%Candidate{} = candidate, _authority) do
    {:error,
     %{
       code: :REFUSED_DFCM_CANDIDATE_NOT_ADMITTED,
       subject: candidate.id,
       detail: "refused candidate cannot be selected",
       evidence: %{refusals: candidate.refusals}
     }}
  end

  @doc "Return a diversity-preserving high-value frontier rather than one premature winner."
  def frontier(candidates, limit \\ 32) do
    candidates
    |> Enum.filter(&(&1.refusals == []))
    |> Enum.sort_by(fn candidate -> {-candidate.score, candidate.id} end)
    |> Enum.reduce([], fn candidate, acc ->
      if dominated?(candidate, acc) do
        acc
      else
        [candidate | Enum.reject(acc, &dominates?(candidate, &1))]
      end
    end)
    |> Enum.sort_by(fn candidate -> {-candidate.score, candidate.id} end)
    |> Enum.take(limit)
  end

  @doc "Summarize assignments as a stable matrix suitable for ggen input."
  def matrix(candidates) do
    dimensions = dimensions() |> Enum.map(& &1.id)

    %{
      dimensions: dimensions,
      rows:
        Enum.map(candidates, fn candidate ->
          %{
            id: candidate.id,
            status: candidate.status,
            score: candidate.score,
            reversible?: candidate.reversible?,
            assignment: candidate.assignment,
            required_evidence: candidate.required_evidence,
            irreversible_edges: candidate.irreversible_edges
          }
        end)
    }
  end

  @doc "Stable identity of the graph definition."
  def graph_sha256(graph \\ default_graph()), do: sha256(graph)

  @doc "Deterministically hash a DfCM term."
  def sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp dim(id, options, description, authority, default) do
    %Dimension{
      id: id,
      options: options,
      description: description,
      authority: authority,
      default: default,
      metadata: %{reversible_until_selected?: true}
    }
  end

  defp rule(id, severity, description) do
    %Constraint{id: id, severity: severity, description: description, falsifier: id}
  end

  defp assignments([], assignment), do: Stream.map([assignment], & &1)

  defp assignments([%Dimension{} = dim | rest], assignment) do
    dim.options
    |> Stream.flat_map(fn option ->
      assignments(rest, Map.put(assignment, dim.id, option))
    end)
  end

  defp apply_selection(dimensions, selection) do
    Enum.map(dimensions, fn dim ->
      case Map.fetch(selection, dim.id) do
        {:ok, value} -> %{dim | options: [value]}
        :error -> dim
      end
    end)
  end

  defp normalize_selection(selection) when is_list(selection), do: selection |> Map.new() |> normalize_selection()

  defp normalize_selection(selection) when is_map(selection) do
    Map.new(selection, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), normalize_atom(value)}
      {key, value} -> {key, normalize_atom(value)}
    end)
  end

  defp normalize_atom(value) when is_binary(value), do: String.to_atom(value)
  defp normalize_atom(value), do: value

  defp check(:active_active_requires_strong_or_idempotent, a) do
    if a.deployment_topology == :multi_region_active_active and
         a.consistency_model != :strong and
         a.execution_mode != :receipted_write_runtime,
      do: {:refused, %{topology: a.deployment_topology, consistency: a.consistency_model}},
      else: :ok
  end

  defp check(:cellular_requires_partitioning, a) do
    if a.deployment_topology == :cellular_multi_region and a.partition_strategy == :none,
      do: {:refused, %{partition_strategy: :none}},
      else: :ok
  end

  defp check(:database_per_tenant_requires_isolated_pool, a) do
    if a.tenancy_model == :database_per_tenant and a.runtime_isolation == :shared_pool,
      do: {:refused, %{tenancy_model: a.tenancy_model, runtime_isolation: a.runtime_isolation}},
      else: :ok
  end

  defp check(:sovereign_residency_requires_sovereign_distribution, a) do
    if a.data_residency == :sovereign_cell and
         a.artifact_distribution not in [:sovereign_registry, :offline_bundle],
      do: {:refused, %{data_residency: a.data_residency, artifact_distribution: a.artifact_distribution}},
      else: :ok
  end

  defp check(:air_gap_requires_offline_distribution, a) do
    if a.network_boundary == :air_gapped and a.artifact_distribution != :offline_bundle,
      do: {:refused, %{network_boundary: :air_gapped, artifact_distribution: a.artifact_distribution}},
      else: :ok
  end

  defp check(:air_gap_forbids_external_protocol, a) do
    if a.network_boundary == :air_gapped and a.obda_topology == :external_protocol,
      do: {:refused, %{network_boundary: :air_gapped, obda_topology: :external_protocol}},
      else: :ok
  end

  defp check(:write_runtime_requires_receipted_observability, a) do
    if a.execution_mode == :receipted_write_runtime and a.observability != :open_telemetry_receipts,
      do: {:refused, %{execution_mode: a.execution_mode, observability: a.observability}},
      else: :ok
  end

  defp check(:write_runtime_requires_safe_migration, a) do
    if a.execution_mode == :receipted_write_runtime and a.migration_strategy == :offline,
      do: {:refused, %{execution_mode: a.execution_mode, migration_strategy: :offline}},
      else: :ok
  end

  defp check(:active_active_dr_requires_multi_region, a) do
    if a.disaster_recovery == :active_active and
         a.deployment_topology not in [:multi_region_active_active, :cellular_multi_region],
      do: {:refused, %{disaster_recovery: :active_active, deployment_topology: a.deployment_topology}},
      else: :ok
  end

  defp check(:multi_region_availability_requires_multi_region_deployment, a) do
    if a.availability_model == :multi_region and a.deployment_topology == :single_region,
      do: {:refused, %{availability_model: :multi_region, deployment_topology: :single_region}},
      else: :ok
  end

  defp check(:strong_consistency_requires_nonlocal_coordination, a) do
    if a.consistency_model == :strong and
         a.deployment_topology in [:multi_region_active_active, :cellular_multi_region] and
         a.control_plane == :centralized,
      do: {:refused, %{consistency_model: :strong, control_plane: :centralized}},
      else: :ok
  end

  defp check(:fedramp_high_requires_airgap_or_zero_trust, a) do
    if a.compliance_profile == :fedramp_high and
         a.network_boundary not in [:zero_trust_mesh, :air_gapped],
      do: {:refused, %{compliance_profile: :fedramp_high, network_boundary: a.network_boundary}},
      else: :ok
  end

  defp check(:regulated_requires_signed_distribution, a) do
    if a.compliance_profile in [:pci, :hipaa, :sox, :fedramp_high] and
         a.artifact_distribution == :single_registry,
      do: {:refused, %{compliance_profile: a.compliance_profile, artifact_distribution: :single_registry}},
      else: :ok
  end

  defp check(:pci_forbids_shared_pool, a) do
    if a.compliance_profile == :pci and a.runtime_isolation == :shared_pool,
      do: {:refused, %{compliance_profile: :pci, runtime_isolation: :shared_pool}},
      else: :ok
  end

  defp check(:hipaa_forbids_unrestricted_residency, a) do
    if a.compliance_profile == :hipaa and a.data_residency == :unrestricted,
      do: {:refused, %{compliance_profile: :hipaa, data_residency: :unrestricted}},
      else: :ok
  end

  defp check(:dual_engine_requires_read_capability, a) do
    if a.obda_topology == :dual_engine_differential and a.execution_mode == :compile_only,
      do: {:refused, %{obda_topology: :dual_engine_differential, execution_mode: :compile_only}},
      else: :ok
  end

  defp check(:semantic_materialization_requires_read_runtime, a) do
    if a.cache_strategy == :semantic_materialization and a.execution_mode == :compile_only,
      do: {:refused, %{cache_strategy: :semantic_materialization, execution_mode: :compile_only}},
      else: :ok
  end

  defp check(:shadow_dual_write_requires_receipted_write, a) do
    if a.migration_strategy == :shadow_dual_write and a.execution_mode != :receipted_write_runtime,
      do: {:refused, %{migration_strategy: :shadow_dual_write, execution_mode: a.execution_mode}},
      else: :ok
  end

  defp check(:cell_progressive_requires_cellular, a) do
    if a.release_strategy == :cell_progressive and a.deployment_topology != :cellular_multi_region,
      do: {:refused, %{release_strategy: :cell_progressive, deployment_topology: a.deployment_topology}},
      else: :ok
  end

  defp check(:cellular_control_plane_requires_cellular_deployment, a) do
    if a.control_plane == :cellular_federated and a.deployment_topology != :cellular_multi_region,
      do: {:refused, %{control_plane: :cellular_federated, deployment_topology: a.deployment_topology}},
      else: :ok
  end

  defp check(:offline_bundle_prefers_airgap, a) do
    if a.artifact_distribution == :offline_bundle and
         a.network_boundary != :air_gapped and
         a.data_residency != :sovereign_cell,
      do: {:refused, %{artifact_distribution: :offline_bundle}},
      else: :ok
  end

  defp check(:single_region_limits_dr, a) do
    if a.deployment_topology == :single_region and a.disaster_recovery in [:hot_standby, :active_active],
      do: {:refused, %{deployment_topology: :single_region, disaster_recovery: a.disaster_recovery}},
      else: :ok
  end

  defp check(:shared_schema_limits_regulated_isolation, a) do
    if a.tenancy_model == :shared_schema and a.compliance_profile in [:pci, :hipaa, :fedramp_high],
      do: {:refused, %{tenancy_model: :shared_schema, compliance_profile: a.compliance_profile}},
      else: :ok
  end

  defp check(_unknown, _assignment), do: :ok

  defp refusal(constraint, evidence) do
    %{
      code: :REFUSED_DFCM_CONSTRAINT,
      rule: constraint.id,
      detail: constraint.description,
      evidence: evidence
    }
  end

  defp warning(constraint, evidence) do
    %{code: :DFCM_ADVISORY, rule: constraint.id, detail: constraint.description, evidence: evidence}
  end

  defp consequences(a) do
    []
    |> add_if(a.deployment_topology in [:multi_region_active_active, :cellular_multi_region], :cross_region_coordination)
    |> add_if(a.tenancy_model in [:database_per_tenant, :cell_per_tenant_class], :tenant_lifecycle_orchestration)
    |> add_if(a.execution_mode == :receipted_write_runtime, :brce_do_path)
    |> add_if(a.obda_topology == :dual_engine_differential, :differential_query_cost)
    |> add_if(a.partition_strategy != :none, :partition_key_governance)
    |> add_if(a.data_residency != :unrestricted, :residency_routing)
    |> add_if(a.compliance_profile != :baseline, :control_evidence_binding)
    |> add_if(a.cache_strategy == :semantic_materialization, :cache_invalidation_contract)
    |> add_if(a.release_strategy in [:canary, :cell_progressive], :progressive_release_observation)
    |> Enum.reverse()
  end

  defp irreversible_edges(a) do
    []
    |> add_if(a.tenancy_model == :database_per_tenant, :database_per_tenant_physicalization)
    |> add_if(a.data_residency == :sovereign_cell, :sovereign_data_placement)
    |> add_if(a.execution_mode == :receipted_write_runtime, :remote_write_actuation)
    |> add_if(a.migration_strategy == :shadow_dual_write, :dual_write_side_effects)
    |> Enum.reverse()
  end

  defp required_evidence(a) do
    [:semantic_mapping_receipt, :deterministic_generation_receipt, :exact_head_build]
    |> add_if(a.execution_mode != :compile_only, :runtime_subject_observation)
    |> add_if(a.obda_topology in [:ontop_protocol, :external_protocol, :dual_engine_differential], :sparql_protocol_observation)
    |> add_if(a.obda_topology == :dual_engine_differential, :differential_parity_receipt)
    |> add_if(a.deployment_topology != :single_region, :regional_failover_observation)
    |> add_if(a.disaster_recovery != :backup_restore, :disaster_recovery_drill_receipt)
    |> add_if(a.execution_mode == :receipted_write_runtime, :brce_actuation_receipt)
    |> add_if(a.compliance_profile != :baseline, :control_attestation_set)
    |> add_if(a.artifact_distribution != :single_registry, :artifact_replication_receipt)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp score(a, warnings, irreversible) do
    availability =
      case a.deployment_topology do
        :single_region -> 10
        :multi_region_active_passive -> 25
        :multi_region_active_active -> 35
        :cellular_multi_region -> 40
      end

    isolation =
      case a.runtime_isolation do
        :shared_pool -> 5
        :tenant_pool -> 15
        :cell_pool -> 25
        :dedicated_workload -> 30
      end

    observability = if a.observability == :open_telemetry_receipts, do: 20, else: 8
    safety = if a.execution_mode == :receipted_write_runtime, do: 18, else: 20
    reversibility = max(0, 20 - length(irreversible) * 6)
    warning_penalty = length(warnings) * 4

    availability + isolation + observability + safety + reversibility - warning_penalty
  end

  defp dominates?(left, right) do
    left.score >= right.score and
      length(left.irreversible_edges) <= length(right.irreversible_edges) and
      Map.get(left.assignment, :deployment_topology) == Map.get(right.assignment, :deployment_topology) and
      left.id != right.id
  end

  defp dominated?(candidate, frontier), do: Enum.any?(frontier, &dominates?(&1, candidate))

  defp enumeration_receipt(graph, selection, candidates, max_candidates, max_examined) do
    admitted = Enum.count(candidates, &(&1.refusals == []))
    refused = Enum.count(candidates, &(&1.refusals != []))

    histogram =
      candidates
      |> Enum.flat_map(& &1.refusals)
      |> Enum.map(&Map.get(&1, :rule, Map.get(&1, :code)))
      |> Enum.frequencies()

    base = %EnumerationReceipt{
      graph_sha256: graph_sha256(graph),
      selection_sha256: sha256(selection),
      status: :PARTIAL_ALIVE,
      standing: :bounded_configuration_exploration,
      examined: min(max_examined, max_candidates),
      admitted: admitted,
      refused: refused,
      returned: length(candidates),
      truncated?: length(candidates) >= max_candidates,
      selected: selection,
      candidate_ids: Enum.map(candidates, & &1.id),
      refusal_histogram: histogram
    }

    %{base | receipt_sha256: sha256(Map.from_struct(base))}
  end

  defp add_if(list, true, value), do: [value | list]
  defp add_if(list, false, _value), do: list

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp present?(value), do: is_binary(value) and value != ""

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
