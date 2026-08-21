# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.DfCM do
  @moduledoc """
  Bounded Design for Combinatorial Maximalism calculus for Fortune-5 deployment.

  The graph preserves a maximal reversible set of lawful configurations before
  irreversible selection. It is pure: enumeration, admission, scoring and
  selection manufacture no infrastructure side effects. Enumeration is lazy and
  explicitly bounded, so a very large logical design space does not imply an
  unbounded in-memory product.
  """

  defmodule Dimension do
    @moduledoc "One reversible design dimension."
    @enforce_keys [:id, :options]
    defstruct [:id, :description, :authority, options: [], default: nil, metadata: %{}]
    @type t :: %__MODULE__{}
  end

  defmodule Constraint do
    @moduledoc "Named admission rule; rules are data, never ambient authority."
    @enforce_keys [:id, :severity]
    defstruct [:id, :severity, :description, :falsifier]
    @type t :: %__MODULE__{}
  end

  defmodule Candidate do
    @moduledoc "One fully assigned design candidate."
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

    @type t :: %__MODULE__{}
  end

  defmodule Graph do
    @moduledoc "Canonical bounded DfCM design graph."
    defstruct version: "fortune5-dfcm-v2",
              dimensions: [],
              constraints: [],
              bounds: %{max_candidates: 10_000, max_examined: 1_000_000},
              metadata: %{}

    @type t :: %__MODULE__{}
  end

  defmodule EnumerationReceipt do
    @moduledoc "Deterministic receipt for one bounded exploration pass."
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

    @type t :: %__MODULE__{}
  end

  @dimension_specs [
    {:deployment_topology,
     [:single_region, :multi_region_active_passive, :multi_region_active_active, :cellular_multi_region],
     :multi_region_active_passive, :platform_architecture, "physical deployment topology"},
    {:tenancy_model,
     [:shared_schema, :schema_per_tenant, :database_per_tenant, :cell_per_tenant_class],
     :shared_schema, :data_governance, "tenant isolation topology"},
    {:consistency_model, [:eventual, :read_after_write, :strong], :read_after_write,
     :data_architecture, "cross-node semantic consistency target"},
    {:execution_mode, [:compile_only, :read_only_runtime, :receipted_write_runtime],
     :read_only_runtime, :security_authority, "maximum runtime authority"},
    {:obda_topology, [:ontop_cli, :ontop_protocol, :external_protocol, :dual_engine_differential],
     :ontop_protocol, :semantic_platform, "virtual RDF execution topology"},
    {:partition_strategy, [:none, :tenant_hash, :semantic_class, :geography, :hybrid], :tenant_hash,
     :data_architecture, "horizontal partition key family"},
    {:availability_model, [:zonal, :regional, :multi_region], :multi_region, :sre,
     "failure-domain availability target"},
    {:disaster_recovery, [:backup_restore, :warm_standby, :hot_standby, :active_active], :hot_standby,
     :sre, "disaster recovery posture"},
    {:observability, [:telemetry, :open_telemetry, :open_telemetry_receipts],
     :open_telemetry_receipts, :observability, "trace metric and receipt correlation"},
    {:workload_identity, [:workload_identity, :spiffe, :oidc_federated], :spiffe, :security,
     "machine identity source"},
    {:secret_provider, [:external_env, :vault, :cloud_kms, :external_secrets_operator],
     :external_secrets_operator, :security, "secret materialization provider"},
    {:release_strategy, [:rolling, :blue_green, :canary, :cell_progressive], :canary,
     :release_engineering, "release rollout strategy"},
    {:migration_strategy, [:offline, :expand_contract, :shadow_dual_read, :shadow_dual_write],
     :expand_contract, :data_architecture, "schema and semantic migration strategy"},
    {:network_boundary, [:private_service, :zero_trust_mesh, :air_gapped], :zero_trust_mesh,
     :security, "network trust boundary"},
    {:data_residency, [:unrestricted, :country_pinned, :region_pinned, :sovereign_cell],
     :region_pinned, :data_governance, "residency constraint class"},
    {:compliance_profile, [:baseline, :soc2, :pci, :hipaa, :sox, :fedramp_high], :baseline,
     :governance, "evidence control profile"},
    {:cache_strategy, [:none, :local, :distributed, :semantic_materialization], :local,
     :performance, "derived semantic cache topology"},
    {:runtime_isolation, [:shared_pool, :tenant_pool, :cell_pool, :dedicated_workload], :cell_pool,
     :platform_architecture, "runtime fault containment boundary"},
    {:artifact_distribution, [:single_registry, :replicated_registry, :sovereign_registry, :offline_bundle],
     :replicated_registry, :release_engineering, "signed artifact distribution topology"},
    {:control_plane, [:centralized, :regional_federated, :cellular_federated], :regional_federated,
     :platform_architecture, "operator control-plane topology"}
  ]

  @constraint_specs [
    {:active_active_requires_strong_or_idempotent, :hard,
     "active/active requires strong consistency or receipted idempotent writes"},
    {:cellular_requires_partitioning, :hard, "cellular deployment requires partitioning"},
    {:database_per_tenant_requires_isolated_pool, :hard,
     "database-per-tenant cannot use a shared runtime pool"},
    {:sovereign_residency_requires_sovereign_distribution, :hard,
     "sovereign residency requires sovereign or offline artifact distribution"},
    {:air_gap_requires_offline_distribution, :hard,
     "air-gapped runtime requires offline artifact distribution"},
    {:air_gap_forbids_external_protocol, :hard,
     "air-gapped runtime cannot depend on an ambient external SPARQL endpoint"},
    {:write_runtime_requires_receipted_observability, :hard,
     "receipted writes require trace-to-receipt observability"},
    {:write_runtime_requires_safe_migration, :hard,
     "receipted write runtime cannot use offline-only migration"},
    {:active_active_dr_requires_multi_region, :hard, "active/active DR requires multi-region deployment"},
    {:multi_region_availability_requires_multi_region_deployment, :hard,
     "multi-region availability requires a multi-region deployment"},
    {:strong_consistency_requires_nonlocal_coordination, :hard,
     "strong multi-region consistency requires federated coordination"},
    {:fedramp_high_requires_airgap_or_zero_trust, :hard,
     "FedRAMP High requires zero-trust or air-gapped networking"},
    {:regulated_requires_signed_distribution, :hard,
     "regulated profiles cannot depend on one mutable registry"},
    {:pci_forbids_shared_pool, :hard, "PCI candidate cannot use a fully shared runtime pool"},
    {:hipaa_forbids_unrestricted_residency, :hard,
     "HIPAA candidate requires an explicit residency policy"},
    {:dual_engine_requires_read_capability, :hard,
     "differential OBDA execution requires runtime read capability"},
    {:semantic_materialization_requires_read_runtime, :hard,
     "semantic materialization requires runtime read capability"},
    {:shadow_dual_write_requires_receipted_write, :hard,
     "shadow dual-write requires receipted write runtime"},
    {:cell_progressive_requires_cellular, :hard,
     "cell-progressive release requires cellular deployment"},
    {:cellular_control_plane_requires_cellular_deployment, :hard,
     "cellular control plane requires cellular deployment"},
    {:offline_bundle_prefers_airgap, :advisory,
     "offline bundles are normally selected for air-gapped or sovereign deployments"},
    {:single_region_limits_dr, :advisory,
     "single-region topology materially limits high-availability DR"},
    {:shared_schema_limits_regulated_isolation, :advisory,
     "shared schema increases evidence burden for regulated isolation"}
  ]

  @dimension_ids Enum.map(@dimension_specs, &elem(&1, 0))
  @option_lookup Map.new(@dimension_specs, fn {id, options, _default, _authority, _description} ->
                   {id, Map.new(options, &{Atom.to_string(&1), &1})}
                 end)
  @dimension_key_lookup Map.new(@dimension_ids, &{Atom.to_string(&1), &1})

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

  @doc "Canonical design dimensions."
  @spec dimensions() :: [Dimension.t()]
  def dimensions do
    Enum.map(@dimension_specs, fn {id, options, default, authority, description} ->
      %Dimension{
        id: id,
        options: options,
        default: default,
        authority: authority,
        description: description,
        metadata: %{reversible_until_selected?: true}
      }
    end)
  end

  @doc "Canonical cross-dimensional constraints."
  @spec constraints() :: [Constraint.t()]
  def constraints do
    Enum.map(@constraint_specs, fn {id, severity, description} ->
      %Constraint{id: id, severity: severity, description: description, falsifier: id}
    end)
  end

  @doc "Return the full default assignment without performing selection."
  @spec default_assignment(Graph.t()) :: map()
  def default_assignment(graph \\ default_graph()) do
    Map.new(graph.dimensions, &{&1.id, &1.default})
  end

  @doc "Compute the logical product cardinality without enumerating it."
  @spec logical_cardinality(Graph.t(), map() | keyword()) :: non_neg_integer()
  def logical_cardinality(graph \\ default_graph(), selection \\ %{}) do
    with {:ok, normalized} <- normalize_selection(graph, selection),
         {:ok, dimensions} <- apply_selection(graph.dimensions, normalized) do
      Enum.reduce(dimensions, 1, fn dimension, acc -> acc * length(dimension.options) end)
    else
      {:error, _} -> 0
    end
  end

  @doc "Lazily enumerate bounded lawful candidates and preserve an exact exploration receipt."
  @spec enumerate(Graph.t(), keyword()) ::
          {:ok, [Candidate.t()], EnumerationReceipt.t()} | {:error, map()}
  def enumerate(graph \\ default_graph(), opts \\ []) do
    max_candidates = positive_bound(Keyword.get(opts, :max_candidates, graph.bounds.max_candidates), :max_candidates)
    max_examined = positive_bound(Keyword.get(opts, :max_examined, graph.bounds.max_examined), :max_examined)
    include_refused? = Keyword.get(opts, :include_refused?, false)

    with {:ok, max_candidates} <- max_candidates,
         {:ok, max_examined} <- max_examined,
         {:ok, selection} <- normalize_selection(graph, Keyword.get(opts, :select, %{})),
         {:ok, constrained_dimensions} <- apply_selection(graph.dimensions, selection) do
      logical_cardinality =
        Enum.reduce(constrained_dimensions, 1, fn dimension, acc -> acc * length(dimension.options) end)

      initial = %{candidates: [], examined: 0, admitted: 0, refused: 0, histogram: %{}}

      result =
        constrained_dimensions
        |> assignments(%{})
        |> Enum.reduce_while(initial, fn assignment, acc ->
          cond do
            acc.examined >= max_examined ->
              {:halt, acc}

            length(acc.candidates) >= max_candidates ->
              {:halt, acc}

            true ->
              candidate = evaluate(graph, assignment)
              admitted? = candidate.refusals == []
              returned? = include_refused? or admitted?

              next = %{
                candidates: if(returned?, do: [candidate | acc.candidates], else: acc.candidates),
                examined: acc.examined + 1,
                admitted: acc.admitted + if(admitted?, do: 1, else: 0),
                refused: acc.refused + if(admitted?, do: 0, else: 1),
                histogram: merge_refusals(acc.histogram, candidate.refusals)
              }

              {:cont, next}
          end
        end)

      candidates = Enum.reverse(result.candidates)
      truncated? = result.examined < logical_cardinality

      base = %EnumerationReceipt{
        graph_sha256: graph_sha256(graph),
        selection_sha256: sha256(selection),
        status: :PARTIAL_ALIVE,
        standing: :bounded_configuration_exploration,
        examined: result.examined,
        admitted: result.admitted,
        refused: result.refused,
        returned: length(candidates),
        truncated?: truncated?,
        selected: selection,
        candidate_ids: Enum.map(candidates, & &1.id),
        refusal_histogram: result.histogram
      }

      receipt = %{base | receipt_sha256: sha256(Map.from_struct(base))}
      {:ok, candidates, receipt}
    end
  end

  @doc "Evaluate one fully assigned candidate against every graph constraint."
  @spec evaluate(Graph.t(), map() | keyword()) :: Candidate.t()
  def evaluate(%Graph{} = graph, assignment) do
    normalized_result = normalize_selection(graph, assignment)

    {normalized, base_refusals} =
      case normalized_result do
        {:ok, value} -> {value, []}
        {:error, refusal} -> {%{}, [refusal]}
      end

    missing =
      graph.dimensions
      |> Enum.map(& &1.id)
      |> Enum.reject(&Map.has_key?(normalized, &1))

    missing_refusals =
      Enum.map(missing, fn id ->
        %{code: :REFUSED_INCOMPLETE_CANDIDATE, subject: id, detail: "candidate omits required dimension", evidence: %{}}
      end)

    {hard, warnings} =
      Enum.reduce(graph.constraints, {[], []}, fn constraint, {hard, warnings} ->
        case check(constraint.id, normalized) do
          :ok ->
            {hard, warnings}

          {:refused, evidence} when constraint.severity == :hard ->
            {[refusal(constraint, evidence) | hard], warnings}

          {:refused, evidence} ->
            {hard, [warning(constraint, evidence) | warnings]}
        end
      end)

    refusals = base_refusals ++ missing_refusals ++ Enum.reverse(hard)
    warnings = Enum.reverse(warnings)
    irreversible = irreversible_edges(normalized)
    candidate_id = sha256(normalized)

    %Candidate{
      id: candidate_id,
      assignment: normalized,
      status: if(refusals == [], do: :ADMITTED, else: :REFUSED),
      standing: if(refusals == [], do: :candidate_constructible, else: :candidate_rejected),
      score: score(normalized, warnings, irreversible),
      reversible?: irreversible == [],
      selected?: false,
      refusals: refusals,
      warnings: warnings,
      consequences: consequences(normalized),
      required_evidence: required_evidence(normalized),
      irreversible_edges: irreversible
    }
  end

  @doc "Select one admitted candidate only with explicit external selection authority."
  @spec select(Candidate.t(), map()) :: {:ok, Candidate.t()} | {:error, map()}
  def select(%Candidate{refusals: []} = candidate, authority) when is_map(authority) do
    authority_id = value(authority, :receipt_sha256)
    authorized? = value(authority, :authorized?) == true

    if authorized? and present_hash?(authority_id) do
      {:ok,
       %{
         candidate
         | selected?: true,
           standing: :selected_for_construct,
           consequences: [{:selection_authority, authority_id} | candidate.consequences]
       }}
    else
      {:error,
       %{
         code: :REFUSED_DFCM_SELECTION_WITHOUT_AUTHORITY,
         subject: candidate.id,
         detail: "selection requires authorized?: true and a 64-hex receipt_sha256",
         evidence: redact_authority(authority)
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

  @doc "Return a diversity-preserving high-value frontier instead of one premature winner."
  @spec frontier([Candidate.t()], pos_integer()) :: [Candidate.t()]
  def frontier(candidates, limit \\ 32) when is_integer(limit) and limit > 0 do
    candidates
    |> Enum.filter(&(&1.refusals == []))
    |> Enum.sort_by(fn candidate -> {-candidate.score, length(candidate.irreversible_edges), candidate.id} end)
    |> Enum.reduce([], fn candidate, acc ->
      if dominated?(candidate, acc) do
        acc
      else
        [candidate | Enum.reject(acc, &dominates?(candidate, &1))]
      end
    end)
    |> Enum.sort_by(fn candidate -> {-candidate.score, length(candidate.irreversible_edges), candidate.id} end)
    |> Enum.take(limit)
  end

  @doc "Stable matrix projection suitable for ggen input."
  def matrix(candidates) do
    %{
      dimensions: @dimension_ids,
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

  @doc "Stable graph identity."
  def graph_sha256(graph \\ default_graph()), do: sha256(graph)

  @doc "Deterministically hash one DfCM term."
  def sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp assignments([], assignment), do: Stream.map([assignment], & &1)

  defp assignments([%Dimension{} = dimension | rest], assignment) do
    Stream.flat_map(dimension.options, fn option ->
      assignments(rest, Map.put(assignment, dimension.id, option))
    end)
  end

  defp normalize_selection(%Graph{} = graph, selection) when is_list(selection) do
    normalize_selection(graph, Map.new(selection))
  end

  defp normalize_selection(%Graph{} = graph, selection) when is_map(selection) do
    Enum.reduce_while(selection, {:ok, %{}}, fn {raw_key, raw_value}, {:ok, acc} ->
      with {:ok, key} <- normalize_dimension_key(raw_key),
           {:ok, dimension} <- fetch_dimension(graph, key),
           {:ok, option} <- normalize_option(dimension, raw_value) do
        {:cont, {:ok, Map.put(acc, key, option)}}
      else
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp normalize_selection(_graph, other) do
    {:error,
     %{
       code: :REFUSED_INVALID_DFCM_SELECTION,
       subject: :selection,
       detail: "DfCM selection must be a map or keyword list",
       evidence: %{type: inspect(other)}
     }}
  end

  defp normalize_dimension_key(key) when is_atom(key) and key in @dimension_ids, do: {:ok, key}

  defp normalize_dimension_key(key) when is_binary(key) do
    case Map.fetch(@dimension_key_lookup, key) do
      {:ok, id} -> {:ok, id}
      :error -> unknown_dimension(key)
    end
  end

  defp normalize_dimension_key(key), do: unknown_dimension(key)

  defp unknown_dimension(key) do
    {:error,
     %{
       code: :REFUSED_UNKNOWN_DFCM_DIMENSION,
       subject: key,
       detail: "selection references a dimension outside the admitted graph",
       evidence: %{allowed: @dimension_ids}
     }}
  end

  defp fetch_dimension(graph, id) do
    case Enum.find(graph.dimensions, &(&1.id == id)) do
      nil -> unknown_dimension(id)
      dimension -> {:ok, dimension}
    end
  end

  defp normalize_option(%Dimension{id: id, options: options}, value) when value in options,
    do: {:ok, value}

  defp normalize_option(%Dimension{id: id, options: options}, value) when is_binary(value) do
    option_lookup = Map.fetch!(@option_lookup, id)

    case Map.fetch(option_lookup, value) do
      {:ok, option} -> {:ok, option}
      :error -> invalid_option(id, value, options)
    end
  end

  defp normalize_option(%Dimension{id: id, options: options}, value),
    do: invalid_option(id, value, options)

  defp invalid_option(id, value, options) do
    {:error,
     %{
       code: :REFUSED_INVALID_DFCM_OPTION,
       subject: id,
       detail: "selection references an option outside the admitted dimension",
       evidence: %{value: inspect(value), allowed: options}
     }}
  end

  defp apply_selection(dimensions, selection) do
    result =
      Enum.map(dimensions, fn dimension ->
        case Map.fetch(selection, dimension.id) do
          {:ok, value} -> %{dimension | options: [value]}
          :error -> dimension
        end
      end)

    {:ok, result}
  end

  defp positive_bound(value, _name) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_bound(value, name) do
    {:error,
     %{
       code: :REFUSED_INVALID_DFCM_BOUND,
       subject: name,
       detail: "enumeration bound must be a positive integer",
       evidence: %{value: inspect(value)}
     }}
  end

  defp merge_refusals(histogram, refusals) do
    Enum.reduce(refusals, histogram, fn refusal, acc ->
      key = Map.get(refusal, :rule, Map.get(refusal, :code, :UNKNOWN_REFUSAL))
      Map.update(acc, key, 1, &(&1 + 1))
    end)
  end

  defp check(_id, assignment) when map_size(assignment) < 20, do: :ok

  defp check(:active_active_requires_strong_or_idempotent, a) do
    reject(
      a.deployment_topology == :multi_region_active_active and
        a.consistency_model != :strong and a.execution_mode != :receipted_write_runtime,
      %{topology: a.deployment_topology, consistency: a.consistency_model}
    )
  end

  defp check(:cellular_requires_partitioning, a),
    do: reject(a.deployment_topology == :cellular_multi_region and a.partition_strategy == :none, %{partition_strategy: a.partition_strategy})

  defp check(:database_per_tenant_requires_isolated_pool, a),
    do: reject(a.tenancy_model == :database_per_tenant and a.runtime_isolation == :shared_pool, %{tenancy_model: a.tenancy_model, runtime_isolation: a.runtime_isolation})

  defp check(:sovereign_residency_requires_sovereign_distribution, a),
    do: reject(a.data_residency == :sovereign_cell and a.artifact_distribution not in [:sovereign_registry, :offline_bundle], %{data_residency: a.data_residency, artifact_distribution: a.artifact_distribution})

  defp check(:air_gap_requires_offline_distribution, a),
    do: reject(a.network_boundary == :air_gapped and a.artifact_distribution != :offline_bundle, %{network_boundary: a.network_boundary, artifact_distribution: a.artifact_distribution})

  defp check(:air_gap_forbids_external_protocol, a),
    do: reject(a.network_boundary == :air_gapped and a.obda_topology == :external_protocol, %{network_boundary: a.network_boundary, obda_topology: a.obda_topology})

  defp check(:write_runtime_requires_receipted_observability, a),
    do: reject(a.execution_mode == :receipted_write_runtime and a.observability != :open_telemetry_receipts, %{execution_mode: a.execution_mode, observability: a.observability})

  defp check(:write_runtime_requires_safe_migration, a),
    do: reject(a.execution_mode == :receipted_write_runtime and a.migration_strategy == :offline, %{execution_mode: a.execution_mode, migration_strategy: a.migration_strategy})

  defp check(:active_active_dr_requires_multi_region, a),
    do: reject(a.disaster_recovery == :active_active and a.deployment_topology not in [:multi_region_active_active, :cellular_multi_region], %{disaster_recovery: a.disaster_recovery, deployment_topology: a.deployment_topology})

  defp check(:multi_region_availability_requires_multi_region_deployment, a),
    do: reject(a.availability_model == :multi_region and a.deployment_topology == :single_region, %{availability_model: a.availability_model, deployment_topology: a.deployment_topology})

  defp check(:strong_consistency_requires_nonlocal_coordination, a),
    do: reject(a.consistency_model == :strong and a.deployment_topology in [:multi_region_active_active, :cellular_multi_region] and a.control_plane == :centralized, %{consistency_model: a.consistency_model, control_plane: a.control_plane})

  defp check(:fedramp_high_requires_airgap_or_zero_trust, a),
    do: reject(a.compliance_profile == :fedramp_high and a.network_boundary not in [:zero_trust_mesh, :air_gapped], %{compliance_profile: a.compliance_profile, network_boundary: a.network_boundary})

  defp check(:regulated_requires_signed_distribution, a),
    do: reject(a.compliance_profile in [:pci, :hipaa, :sox, :fedramp_high] and a.artifact_distribution == :single_registry, %{compliance_profile: a.compliance_profile, artifact_distribution: a.artifact_distribution})

  defp check(:pci_forbids_shared_pool, a),
    do: reject(a.compliance_profile == :pci and a.runtime_isolation == :shared_pool, %{compliance_profile: a.compliance_profile, runtime_isolation: a.runtime_isolation})

  defp check(:hipaa_forbids_unrestricted_residency, a),
    do: reject(a.compliance_profile == :hipaa and a.data_residency == :unrestricted, %{compliance_profile: a.compliance_profile, data_residency: a.data_residency})

  defp check(:dual_engine_requires_read_capability, a),
    do: reject(a.obda_topology == :dual_engine_differential and a.execution_mode == :compile_only, %{obda_topology: a.obda_topology, execution_mode: a.execution_mode})

  defp check(:semantic_materialization_requires_read_runtime, a),
    do: reject(a.cache_strategy == :semantic_materialization and a.execution_mode == :compile_only, %{cache_strategy: a.cache_strategy, execution_mode: a.execution_mode})

  defp check(:shadow_dual_write_requires_receipted_write, a),
    do: reject(a.migration_strategy == :shadow_dual_write and a.execution_mode != :receipted_write_runtime, %{migration_strategy: a.migration_strategy, execution_mode: a.execution_mode})

  defp check(:cell_progressive_requires_cellular, a),
    do: reject(a.release_strategy == :cell_progressive and a.deployment_topology != :cellular_multi_region, %{release_strategy: a.release_strategy, deployment_topology: a.deployment_topology})

  defp check(:cellular_control_plane_requires_cellular_deployment, a),
    do: reject(a.control_plane == :cellular_federated and a.deployment_topology != :cellular_multi_region, %{control_plane: a.control_plane, deployment_topology: a.deployment_topology})

  defp check(:offline_bundle_prefers_airgap, a),
    do: reject(a.artifact_distribution == :offline_bundle and a.network_boundary != :air_gapped and a.data_residency != :sovereign_cell, %{artifact_distribution: a.artifact_distribution})

  defp check(:single_region_limits_dr, a),
    do: reject(a.deployment_topology == :single_region and a.disaster_recovery in [:hot_standby, :active_active], %{deployment_topology: a.deployment_topology, disaster_recovery: a.disaster_recovery})

  defp check(:shared_schema_limits_regulated_isolation, a),
    do: reject(a.tenancy_model == :shared_schema and a.compliance_profile in [:pci, :hipaa, :fedramp_high], %{tenancy_model: a.tenancy_model, compliance_profile: a.compliance_profile})

  defp check(_unknown, _assignment), do: :ok

  defp reject(true, evidence), do: {:refused, evidence}
  defp reject(false, _evidence), do: :ok

  defp refusal(constraint, evidence) do
    %{code: :REFUSED_DFCM_CONSTRAINT, rule: constraint.id, detail: constraint.description, evidence: evidence}
  end

  defp warning(constraint, evidence) do
    %{code: :DFCM_ADVISORY, rule: constraint.id, detail: constraint.description, evidence: evidence}
  end

  defp consequences(a) do
    []
    |> add_if(a[:deployment_topology] in [:multi_region_active_active, :cellular_multi_region], :cross_region_coordination)
    |> add_if(a[:tenancy_model] in [:database_per_tenant, :cell_per_tenant_class], :tenant_lifecycle_orchestration)
    |> add_if(a[:execution_mode] == :receipted_write_runtime, :brce_do_path)
    |> add_if(a[:obda_topology] == :dual_engine_differential, :differential_query_cost)
    |> add_if(a[:partition_strategy] not in [nil, :none], :partition_key_governance)
    |> add_if(a[:data_residency] not in [nil, :unrestricted], :residency_routing)
    |> add_if(a[:compliance_profile] not in [nil, :baseline], :control_evidence_binding)
    |> add_if(a[:cache_strategy] == :semantic_materialization, :cache_invalidation_contract)
    |> add_if(a[:release_strategy] in [:canary, :cell_progressive], :progressive_release_observation)
    |> Enum.reverse()
  end

  defp irreversible_edges(a) do
    []
    |> add_if(a[:tenancy_model] == :database_per_tenant, :database_per_tenant_physicalization)
    |> add_if(a[:data_residency] == :sovereign_cell, :sovereign_data_placement)
    |> add_if(a[:execution_mode] == :receipted_write_runtime, :remote_write_actuation)
    |> add_if(a[:migration_strategy] == :shadow_dual_write, :dual_write_side_effects)
    |> Enum.reverse()
  end

  defp required_evidence(a) do
    [:semantic_mapping_receipt, :deterministic_generation_receipt, :exact_head_build]
    |> add_if(a[:execution_mode] not in [nil, :compile_only], :runtime_subject_observation)
    |> add_if(a[:obda_topology] in [:ontop_protocol, :external_protocol, :dual_engine_differential], :sparql_protocol_observation)
    |> add_if(a[:obda_topology] == :dual_engine_differential, :differential_parity_receipt)
    |> add_if(a[:deployment_topology] not in [nil, :single_region], :regional_failover_observation)
    |> add_if(a[:disaster_recovery] not in [nil, :backup_restore], :disaster_recovery_drill_receipt)
    |> add_if(a[:execution_mode] == :receipted_write_runtime, :brce_actuation_receipt)
    |> add_if(a[:compliance_profile] not in [nil, :baseline], :control_attestation_set)
    |> add_if(a[:artifact_distribution] not in [nil, :single_registry], :artifact_replication_receipt)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp score(a, warnings, irreversible) do
    availability =
      case a[:deployment_topology] do
        :single_region -> 10
        :multi_region_active_passive -> 25
        :multi_region_active_active -> 35
        :cellular_multi_region -> 40
        _ -> 0
      end

    isolation =
      case a[:runtime_isolation] do
        :shared_pool -> 5
        :tenant_pool -> 15
        :cell_pool -> 25
        :dedicated_workload -> 30
        _ -> 0
      end

    observability = if a[:observability] == :open_telemetry_receipts, do: 20, else: 8
    safety = if a[:execution_mode] == :receipted_write_runtime, do: 18, else: 20
    reversibility = max(0, 20 - length(irreversible) * 6)
    availability + isolation + observability + safety + reversibility - length(warnings) * 4
  end

  defp dominates?(left, right) do
    left.score >= right.score and
      length(left.irreversible_edges) <= length(right.irreversible_edges) and
      left.assignment[:deployment_topology] == right.assignment[:deployment_topology] and
      left.id != right.id
  end

  defp dominated?(candidate, frontier), do: Enum.any?(frontier, &dominates?(&1, candidate))

  defp add_if(list, true, value), do: [value | list]
  defp add_if(list, false, _value), do: list

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp present_hash?(value) when is_binary(value) do
    String.length(value) == 64 and String.match?(value, ~r/\A[0-9a-fA-F]{64}\z/)
  end

  defp present_hash?(_), do: false

  defp redact_authority(authority) do
    %{
      authorized?: value(authority, :authorized?) == true,
      receipt_present?: present_hash?(value(authority, :receipt_sha256))
    }
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
