# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.Ggen do
  @moduledoc """
  Maximal Fortune-5 ggen manufacturing projection.

  This module does not write files and does not invoke ggen.  It constructs the
  complete path/content graph that ggen may materialize under its own authority.
  The graph includes semantic TTL, the DfCM candidate frontier, capability and
  evidence matrices, security/observability/resilience/release contracts, replay
  metadata, and a self-contained ggen pack source projection.

  Generated operational artifacts are downstream projections of admitted Ash /
  SemanticIR / Mapping identity.  They are never promoted to semantic authority.
  """

  alias AshR2RML.Fortune5.{
    CapabilityGraph,
    DfCM,
    Observability,
    ProductionClosure,
    Release,
    Resilience,
    Security
  }

  @default_frontier 32
  @default_candidates 512
  @fortune5_ns "https://w3id.org/ash-r2rml/fortune5#"

  defmodule ManufactureReceipt do
    @moduledoc "Receipt for one constructed Fortune-5 ggen path/content graph."
    defstruct [
      :status,
      :standing,
      :semantic_source,
      :semantic_subject_sha256,
      :mapping_sha256,
      :dfcm_graph_sha256,
      :dfcm_enumeration_receipt_sha256,
      :capability_graph_sha256,
      :capability_admission_receipt_sha256,
      :production_contract_sha256,
      :files_sha256,
      :receipt_sha256,
      :candidate_count,
      :frontier_count,
      :generated_file_count,
      :pack_source_file_count,
      blocked: [],
      verified: [],
      executed: [],
      refused: []
    ]

    @type t :: %__MODULE__{}
  end

  @doc "Manufacture the maximal bounded Fortune-5 path/content graph from Ash or a Mapping.Bundle."
  def compile(resources_or_bundle, opts \\ []) do
    graph = Keyword.get(opts, :graph, DfCM.default_graph())
    contract = Keyword.get(opts, :production_contract, ProductionClosure.default_contract())
    selection = Keyword.get(opts, :select, default_selection(contract))
    max_candidates = Keyword.get(opts, :max_candidates, @default_candidates)
    max_frontier = Keyword.get(opts, :max_frontier, @default_frontier)
    observations = Keyword.get(opts, :capability_observations, [])
    requested = Keyword.get(opts, :capabilities, Enum.map(CapabilityGraph.catalog(), & &1.id))

    with {:ok, semantic} <- AshR2RML.Ggen.TTL.emit(resources_or_bundle),
         {:ok, candidates, enumeration_receipt} <-
           DfCM.enumerate(graph,
             select: selection,
             max_candidates: max_candidates,
             max_examined: Keyword.get(opts, :max_examined, graph.bounds.max_examined)
           ),
         frontier when is_list(frontier) <- DfCM.frontier(candidates, max_frontier) do
      capability_admission = CapabilityGraph.admit(requested, observations)
      production_admission = ProductionClosure.admit(contract)

      manufacture(
        semantic,
        graph,
        candidates,
        frontier,
        enumeration_receipt,
        capability_admission,
        contract,
        production_admission,
        opts
      )
    end
  end

  @doc "Return the ggen pack source files used to project the Fortune-5 operational graph."
  def pack_source_files do
    %{
      "pack.toml" => pack_toml(),
      "ggen.toml" => ggen_toml(),
      "gates/010_semantic_subject.rq" => gate_semantic_subject(),
      "gates/020_candidate_identity.rq" => gate_candidate_identity(),
      "gates/030_candidate_topology.rq" => gate_candidate_topology(),
      "gates/040_authority_boundary.rq" => gate_authority_boundary(),
      "gates/050_capability_closure.rq" => gate_capability_closure(),
      "gates/060_receipt_identity.rq" => gate_receipt_identity(),
      "gates/070_no_ambient_do.rq" => gate_no_ambient_do(),
      "gates/080_runtime_evidence.rq" => gate_runtime_evidence(),
      "queries/candidates.rq" => query_candidates(),
      "queries/capabilities.rq" => query_capabilities(),
      "queries/release_matrix.rq" => query_release_matrix(),
      "queries/authority_matrix.rq" => query_authority_matrix(),
      "templates/candidate_contract.json.tmpl" => template_candidate_contract(),
      "templates/capability_matrix.md.tmpl" => template_capability_matrix(),
      "templates/release_matrix.md.tmpl" => template_release_matrix(),
      "templates/authority_matrix.md.tmpl" => template_authority_matrix()
    }
  end

  @doc "Deterministically project the DfCM/capability graph to RDF consumed by the pack."
  def contract_ttl(frontier, capability_admission, semantic) do
    semantic_subject = semantic_subject_sha256(semantic)

    header = """
    @prefix f5: <#{@fortune5_ns}> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    f5:SemanticSubject a f5:AdmittedSemanticSubject ;
      f5:subjectSha256 "#{semantic_subject}" ;
      f5:constructOnly true .

    f5:AuthorityBoundary a f5:AuthorityContract ;
      f5:selectConstructDoSeparated true ;
      f5:brceOnlyDo true ;
      f5:ambientDo false .

    """

    candidates =
      frontier
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&candidate_ttl/1)
      |> Enum.join("\n")

    capabilities = capability_ttl(capability_admission)
    header <> candidates <> capabilities
  end

  @doc "Verify observed staged artifact hashes against the constructed plan."
  def verify_staged(%{files: files}, observed) when is_map(observed) do
    expected = file_hashes(files)
    observed = normalize_hash_map(observed)

    missing = Map.keys(expected) -- Map.keys(observed)
    extra = Map.keys(observed) -- Map.keys(expected)

    mismatched =
      expected
      |> Enum.flat_map(fn {path, hash} ->
        case Map.fetch(observed, path) do
          {:ok, ^hash} -> []
          {:ok, actual} -> [%{path: path, expected: hash, actual: actual}]
          :error -> []
        end
      end)

    if missing == [] and extra == [] and mismatched == [] do
      {:ok,
       %{
         status: :ALIVE,
         standing: :ggen_staged_projection_hashes_verified,
         files_sha256: sha256(expected)
       }}
    else
      {:error,
       %{
         code: :REFUSED_GGEN_STAGED_HASH_MISMATCH,
         subject: :fortune5_projection,
         evidence: %{missing: missing, extra: extra, mismatched: mismatched}
       }}
    end
  end

  defp manufacture(
         semantic,
         graph,
         candidates,
         frontier,
         enumeration_receipt,
         capability_admission,
         contract,
         production_admission,
         opts
       ) do
    semantic_subject_sha256 = semantic_subject_sha256(semantic)
    production_contract_sha256 = sha256(contract)

    operational_files =
      frontier
      |> Enum.flat_map(fn candidate -> candidate_files(candidate, semantic_subject_sha256, capability_admission) end)
      |> Map.new()

    semantic_files =
      semantic.files
      |> Enum.map(fn {path, content} -> {"semantic/#{path}", content} end)
      |> Map.new()

    pack_files =
      pack_source_files()
      |> Enum.map(fn {path, content} -> {"manufacturing/fortune5-pack/#{path}", content} end)
      |> Map.new()

    contract_ttl = contract_ttl(frontier, capability_admission, semantic)

    core_files = %{
      "manufacturing/fortune5-pack/ontology.ttl" => semantic.files["ontology.ttl"],
      "manufacturing/fortune5-pack/shapes/operational-profile.ttl" =>
        semantic.files["shapes/operational-profile.ttl"],
      "manufacturing/fortune5-pack/r2rml/mapping.ttl" => semantic.files["r2rml/mapping.ttl"],
      "manufacturing/fortune5-pack/fortune5/production-contract.ttl" => contract_ttl,
      "generated/fortune5/dfcm/candidates.json" => json(DfCM.matrix(candidates)),
      "generated/fortune5/dfcm/frontier.json" => json(DfCM.matrix(frontier)),
      "generated/fortune5/dfcm/enumeration-receipt.json" => json(enumeration_receipt),
      "generated/fortune5/capabilities/catalog.json" => json(CapabilityGraph.domain_matrix()),
      "generated/fortune5/capabilities/admission.json" => json(capability_admission),
      "generated/fortune5/capabilities/evidence-plan.json" => json(capability_admission.evidence_plan),
      "generated/fortune5/production/contract.json" => json(contract),
      "generated/fortune5/production/admission.json" => json(production_admission),
      "generated/fortune5/operations/global-verification-plan.json" =>
        json(global_verification_plan(capability_admission)),
      "generated/fortune5/operations/production-readiness.md" =>
        readiness_markdown(frontier, capability_admission, production_admission),
      "generated/fortune5/operations/authority-boundary.md" => authority_markdown(),
      "generated/fortune5/operations/replay-protocol.md" => replay_markdown()
    }

    files = semantic_files |> Map.merge(pack_files) |> Map.merge(core_files) |> Map.merge(operational_files)
    hashes = file_hashes(files)

    base_receipt = %ManufactureReceipt{
      status: :PARTIAL_ALIVE,
      standing: :construct_only_ggen_path_content_graph,
      semantic_source: semantic.source,
      semantic_subject_sha256: semantic_subject_sha256,
      mapping_sha256: semantic.sha256.r2rml,
      dfcm_graph_sha256: DfCM.graph_sha256(graph),
      dfcm_enumeration_receipt_sha256: enumeration_receipt.receipt_sha256,
      capability_graph_sha256: CapabilityGraph.graph_sha256(),
      capability_admission_receipt_sha256: capability_admission.receipt_sha256,
      production_contract_sha256: production_contract_sha256,
      files_sha256: sha256(hashes),
      candidate_count: length(candidates),
      frontier_count: length(frontier),
      generated_file_count: map_size(files),
      pack_source_file_count: map_size(pack_source_files()),
      blocked: blocked(production_admission, capability_admission),
      verified: [],
      executed: [],
      refused: [],
      receipt_sha256: nil
    }

    receipt = %{base_receipt | receipt_sha256: sha256(Map.from_struct(base_receipt))}

    files = Map.put(files, "receipts/fortune5-manufacture.json", json(receipt))

    {:ok,
     %{
       status: :PARTIAL_ALIVE,
       standing: :construct_only,
       source: :ash,
       semantic: semantic,
       dfcm: %{
         graph_sha256: DfCM.graph_sha256(graph),
         enumeration_receipt: enumeration_receipt,
         candidates: candidates,
         frontier: frontier
       },
       capabilities: capability_admission,
       production: production_admission,
       receipt: receipt,
       files: files,
       sha256: file_hashes(files),
       replay: %{
         command_class: :ggen_two_pass,
         requires_exact_toolchain?: true,
         expected_files_sha256: receipt.files_sha256,
         max_frontier: Keyword.get(opts, :max_frontier, @default_frontier)
       }
     }}
  end

  defp candidate_files(candidate, semantic_subject_sha256, capability_admission) do
    prefix = "generated/fortune5/candidates/#{candidate.id}"
    observability = Observability.contract(candidate)
    security = Security.contract(candidate)
    resilience = Resilience.contract(candidate)
    release = Release.plan(candidate)
    verification = candidate_verification_plan(candidate, capability_admission)
    runtime = runtime_contract(candidate)
    tenancy = tenancy_contract(candidate)
    data = data_contract(candidate)
    supply_chain = supply_chain_contract(candidate)

    [
      {"#{prefix}/candidate.json", json(candidate)},
      {"#{prefix}/observability.json", json(observability)},
      {"#{prefix}/security.json", json(security)},
      {"#{prefix}/resilience.json", json(resilience)},
      {"#{prefix}/release.json", json(release)},
      {"#{prefix}/verification-plan.json", json(verification)},
      {"#{prefix}/runtime.json", json(runtime)},
      {"#{prefix}/tenancy.json", json(tenancy)},
      {"#{prefix}/data-governance.json", json(data)},
      {"#{prefix}/supply-chain.json", json(supply_chain)},
      {"#{prefix}/semantic-binding.json",
       json(%{
         semantic_subject_sha256: semantic_subject_sha256,
         candidate_sha256: candidate.id,
         generated_projection?: true,
         semantic_authority?: false
       })},
      {"#{prefix}/runbook.md", candidate_runbook(candidate, verification, resilience, release)}
    ]
  end

  defp runtime_contract(candidate) do
    a = candidate.assignment

    %{
      execution_mode: a.execution_mode,
      obda_topology: a.obda_topology,
      deployment_topology: a.deployment_topology,
      control_plane: a.control_plane,
      runtime_isolation: a.runtime_isolation,
      partition_strategy: a.partition_strategy,
      cache_strategy: a.cache_strategy,
      bounds: %{
        request_timeout_ms: 30_000,
        query_timeout_ms: 30_000,
        max_query_rows: 100_000,
        max_query_bytes: 64 * 1024 * 1024,
        max_queue_ms: 50,
        max_retries: 3
      },
      process_model: %{
        supervised?: true,
        isolated_external_workers?: true,
        bounded_task_supervision?: true,
        crash_only_optional_adapters?: true
      },
      do_authority: if(a.execution_mode == :receipted_write_runtime, do: :brce_only, else: :none)
    }
  end

  defp tenancy_contract(candidate) do
    a = candidate.assignment

    %{
      tenancy_model: a.tenancy_model,
      runtime_isolation: a.runtime_isolation,
      partition_strategy: a.partition_strategy,
      data_residency: a.data_residency,
      invariants: [
        :tenant_context_required,
        :tenant_context_hash_in_receipt,
        :cross_tenant_default_deny,
        :quota_before_execution,
        :residency_before_routing,
        :tenant_id_not_telemetry_label
      ],
      isolation_proof:
        case a.tenancy_model do
          :shared_schema -> :row_policy_and_query_falsifier
          :schema_per_tenant -> :schema_routing_and_cross_schema_falsifier
          :database_per_tenant -> :database_routing_and_credential_falsifier
          :cell_per_tenant_class -> :cell_routing_and_failure_containment_falsifier
        end
    }
  end

  defp data_contract(candidate) do
    a = candidate.assignment

    %{
      residency: a.data_residency,
      consistency: a.consistency_model,
      migration_strategy: a.migration_strategy,
      semantic_identity_may_not_depend_on_physical_region?: true,
      destructive_migration_requires_separate_authority?: true,
      expand_contract_preferred?: a.migration_strategy == :expand_contract,
      schema_and_semantic_drift_must_be_classified?: true,
      retention: %{
        semantic_receipts: :governed,
        raw_external_results: :not_persisted_by_default,
        generated_projections: :reproducible,
        audit_evidence: :policy_bound
      }
    }
  end

  defp supply_chain_contract(candidate) do
    a = candidate.assignment

    %{
      distribution: a.artifact_distribution,
      release_strategy: a.release_strategy,
      required: [
        :immutable_digest,
        :sbom,
        :signature,
        :provenance_attestation,
        :dependency_inventory,
        :vulnerability_policy_result,
        :source_sha,
        :toolchain_identity,
        :ggen_pack_identity,
        :semantic_subject_identity
      ],
      rebuild_between_release_rings?: false,
      mutable_tags_authoritative?: false
    }
  end

  defp candidate_verification_plan(candidate, capability_admission) do
    candidate_evidence =
      candidate.required_evidence
      |> Enum.map(&evidence_command/1)

    %{
      candidate: candidate.id,
      status: :PARTIAL_ALIVE,
      standing: :verification_plan_only,
      candidate_evidence: candidate_evidence,
      capability_evidence: capability_admission.evidence_plan,
      order: [
        :syntax,
        :focused_unit,
        :determinism,
        :static_policy,
        :integration,
        :external_obda,
        :differential_parity,
        :stress,
        :chaos,
        :dr,
        :release_replay,
        :authority
      ],
      no_promotion_without_observed_execution?: true
    }
  end

  defp global_verification_plan(capability_admission) do
    %{
      status: :PARTIAL_ALIVE,
      standing: :verification_plan_constructed,
      exact_head_required?: true,
      gates: [
        %{name: :compile, command: "mix compile --force --warnings-as-errors", proof: :compile},
        %{name: :focused_semantic, command: "mix test test/ash_r2rml_test.exs test/ontology_first_compiler_test.exs", proof: :unit},
        %{name: :fortune5, command: "mix test test/fortune5_*_test.exs", proof: :unit},
        %{name: :full_suite, command: "mix test", proof: :unit_and_integration},
        %{name: :dialyzer, command: "mix dialyzer", proof: :static_analysis},
        %{name: :ggen_two_pass, command: "ggen sync run && ggen sync run", proof: :two_pass},
        %{name: :obda_crown, command: "mix run test/integration/obda_crown.exs", proof: :external_observation},
        %{name: :stress, command_class: :million_concurrency_stress, proof: :stress_1m},
        %{name: :chaos, command_class: :chaos_test, proof: :chaos},
        %{name: :dr, command_class: :disaster_recovery_drill, proof: :dr_drill}
      ],
      capability_evidence: capability_admission.evidence_plan
    }
  end

  defp evidence_command(:semantic_mapping_receipt), do: %{evidence: :semantic_mapping_receipt, command_class: :compile_and_hash}
  defp evidence_command(:deterministic_generation_receipt), do: %{evidence: :deterministic_generation_receipt, command_class: :ggen_two_pass}
  defp evidence_command(:exact_head_build), do: %{evidence: :exact_head_build, command: "mix compile --force --warnings-as-errors"}
  defp evidence_command(:runtime_subject_observation), do: %{evidence: :runtime_subject_observation, command_class: :integration}
  defp evidence_command(:sparql_protocol_observation), do: %{evidence: :sparql_protocol_observation, command_class: :external_obda}
  defp evidence_command(:differential_parity_receipt), do: %{evidence: :differential_parity_receipt, command_class: :multi_engine_differential}
  defp evidence_command(:regional_failover_observation), do: %{evidence: :regional_failover_observation, command_class: :chaos_region_loss}
  defp evidence_command(:disaster_recovery_drill_receipt), do: %{evidence: :disaster_recovery_drill_receipt, command_class: :dr_drill}
  defp evidence_command(:brce_actuation_receipt), do: %{evidence: :brce_actuation_receipt, command_class: :authorized_do}
  defp evidence_command(:control_attestation_set), do: %{evidence: :control_attestation_set, command_class: :control_evidence_export}
  defp evidence_command(:artifact_replication_receipt), do: %{evidence: :artifact_replication_receipt, command_class: :registry_observation}
  defp evidence_command(other), do: %{evidence: other, command_class: :unknown}

  defp default_selection(contract) do
    topology = Map.get(contract, :selected_topology, :multi_region_active_passive)

    %{
      deployment_topology: topology,
      observability: :open_telemetry_receipts,
      workload_identity: :spiffe,
      secret_provider: :external_secrets_operator
    }
  end

  defp blocked({:ok, production}, capabilities), do: production.blocked_checks ++ capability_blocked(capabilities)
  defp blocked({:error, production}, capabilities), do: production.blocked_checks ++ capability_blocked(capabilities)
  defp capability_blocked(capabilities), do: capabilities.unknown ++ capabilities.partial_alive ++ capabilities.blocked ++ capabilities.unsupported ++ capabilities.refused

  defp semantic_subject_sha256(semantic) do
    sha256(%{
      source: semantic.source,
      ontology: semantic.sha256.ontology,
      shacl: semantic.sha256.shacl,
      r2rml: semantic.sha256.r2rml
    })
  end

  defp file_hashes(files) do
    files
    |> Enum.map(fn {path, content} -> {path, :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp normalize_hash_map(map) do
    Map.new(map, fn {path, hash} -> {to_string(path), String.downcase(to_string(hash))} end)
  end

  defp candidate_ttl(candidate) do
    a = candidate.assignment

    predicates = [
      {:candidateId, candidate.id},
      {:score, candidate.score},
      {:deploymentTopology, a.deployment_topology},
      {:tenancyModel, a.tenancy_model},
      {:consistencyModel, a.consistency_model},
      {:executionMode, a.execution_mode},
      {:obdaTopology, a.obda_topology},
      {:partitionStrategy, a.partition_strategy},
      {:availabilityModel, a.availability_model},
      {:disasterRecovery, a.disaster_recovery},
      {:observability, a.observability},
      {:workloadIdentity, a.workload_identity},
      {:secretProvider, a.secret_provider},
      {:releaseStrategy, a.release_strategy},
      {:migrationStrategy, a.migration_strategy},
      {:networkBoundary, a.network_boundary},
      {:dataResidency, a.data_residency},
      {:complianceProfile, a.compliance_profile},
      {:cacheStrategy, a.cache_strategy},
      {:runtimeIsolation, a.runtime_isolation},
      {:artifactDistribution, a.artifact_distribution},
      {:controlPlane, a.control_plane}
    ]

    body =
      predicates
      |> Enum.map(fn {predicate, value} -> "  f5:#{predicate} #{ttl_literal(value)}" end)
      |> Enum.join(" ;\n")

    """
    f5:Candidate_#{candidate.id} a f5:Candidate ;
    #{body} ;
      f5:reversible #{if(candidate.reversible?, do: "true", else: "false")} .
    """
  end

  defp capability_ttl(admission) do
    statuses =
      []
      |> append_status(admission.alive, :ALIVE)
      |> append_status(admission.partial_alive, :PARTIAL_ALIVE)
      |> append_status(admission.unknown, :UNKNOWN)
      |> append_status(admission.blocked, :BLOCKED)
      |> append_status(admission.unsupported, :UNSUPPORTED)
      |> append_status(admission.refused, :REFUSED)

    statuses
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {capability, status} ->
      """
      f5:Capability_#{capability} a f5:Capability ;
        f5:capabilityId "#{capability}" ;
        f5:status "#{status}" .
      """
    end)
    |> Enum.join("\n")
  end

  defp append_status(acc, capabilities, status), do: acc ++ Enum.map(capabilities, &{&1, status})

  defp readiness_markdown(frontier, capabilities, production) do
    production_receipt = case production do {:ok, receipt} -> receipt; {:error, receipt} -> receipt end

    """
    # Fortune-5 Production Readiness Projection

    This document is generated from the admitted production contract. It is not
    production authority and it is not a substitute for observed execution.

    ## Standing

    - DfCM frontier candidates: #{length(frontier)}
    - Capability standing: #{capabilities.status}
    - Production contract standing: #{production_receipt.status}
    - Production ready: #{production_receipt.production_ready?}

    ## Evidence still required

    #{Enum.map_join(capabilities.evidence_plan, "\n", fn item -> "- #{item.capability}: #{item.proof}" end)}

    ## Preserved candidate frontier

    #{Enum.map_join(frontier, "\n", fn candidate -> "- #{candidate.id}: score=#{candidate.score} topology=#{candidate.assignment.deployment_topology} tenancy=#{candidate.assignment.tenancy_model} release=#{candidate.assignment.release_strategy}" end)}
    """
  end

  defp authority_markdown do
    """
    # Authority Boundary

    SELECT, CONSTRUCT, and DO are separate authority classes.

    - Semantic authors may submit candidate semantics; they cannot actuate.
    - AshR2RML may admit and construct deterministic projections; it cannot actuate.
    - ggen may materialize an admitted path/content graph under its own receipt; it cannot grant runtime mutation authority.
    - Hooks manufacture intents; they never actuate.
    - BRCE is the exclusive DO path.
    - Cutover authority is organizational evidence independent of technical parity.

    Any implementation that allows raw RDF, SHACL, template output, planner output,
    model output, or generated source to directly mutate production is refused.
    """
  end

  defp replay_markdown do
    """
    # Replay Protocol

    A Fortune-5 replay binds:

    1. exact source/tree identity;
    2. exact admitted semantic subject identity;
    3. exact Mapping/R2RML identity;
    4. exact DfCM graph and selected candidate identity;
    5. exact ggen pack/config/toolchain identity;
    6. exact external engine/environment identity where relevant;
    7. exact authority receipt for DO or cutover;
    8. exact produced artifact hashes.

    Replay mismatch is a falsifier. Equivalent-looking output without matching
    admitted identities does not inherit the original receipt standing.
    """
  end

  defp candidate_runbook(candidate, verification, resilience, release) do
    a = candidate.assignment

    """
    # Candidate #{candidate.id}

    ## Configuration

    - deployment: #{a.deployment_topology}
    - tenancy: #{a.tenancy_model}
    - consistency: #{a.consistency_model}
    - execution: #{a.execution_mode}
    - OBDA: #{a.obda_topology}
    - partitioning: #{a.partition_strategy}
    - availability: #{a.availability_model}
    - DR: #{a.disaster_recovery}
    - release: #{a.release_strategy}
    - network: #{a.network_boundary}
    - residency: #{a.data_residency}
    - compliance: #{a.compliance_profile}

    ## Required evidence

    #{Enum.map_join(candidate.required_evidence, "\n", &"- #{&1}")}

    ## Failure corpus

    #{Enum.map_join(resilience.failure_catalog, "\n", fn scenario -> "- #{scenario.id}: inject=#{scenario.injection} expect=#{scenario.expected}" end)}

    ## Release phases

    #{Enum.map_join(release.phases, "\n", fn phase -> "- #{phase.name}: #{inspect(phase)}" end)}

    ## Verification

    Standing: #{verification.standing}. Generated commands are a plan only; ALIVE
    requires observed execution against this exact candidate and semantic subject.
    """
  end

  defp pack_toml do
    """
    [pack]
    name = "ash-r2rml-fortune5-pack"
    version = "0.1.0"
    description = "DfCM Fortune-5 projection pack. Consumes AshR2RML-emitted semantic TTL plus production-contract TTL and manufactures candidate, capability, release, and authority projections."
    """
  end

  defp ggen_toml do
    """
    [project]
    name = "ash-r2rml-fortune5"
    version = "0.1.0"
    description = "Fortune-5 DfCM production projections for AshR2RML"
    license = "MIT"

    [ontology]
    source = "ontology.ttl"
    base_iri = "#{@fortune5_ns}"
    imports = [
      "ontology.ttl",
      "shapes/operational-profile.ttl",
      "r2rml/mapping.ttl",
      "fortune5/production-contract.ttl",
    ]

    [ontology.prefixes]
    f5 = "#{@fortune5_ns}"
    rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xsd = "http://www.w3.org/2001/XMLSchema#"

    [validation]
    gates = [
      "gates/010_semantic_subject.rq",
      "gates/020_candidate_identity.rq",
      "gates/030_candidate_topology.rq",
      "gates/040_authority_boundary.rq",
      "gates/050_capability_closure.rq",
      "gates/060_receipt_identity.rq",
      "gates/070_no_ambient_do.rq",
      "gates/080_runtime_evidence.rq",
    ]

    [generation]
    output_dir = "."

    [[generation.rules]]
    name = "candidate-contract"
    query = { file = "queries/candidates.rq" }
    template = { file = "templates/candidate_contract.json.tmpl" }
    output_file = "generated/fortune5/ggen-candidates/{{ candidate_id }}/contract.json"
    skip_empty = true
    mode = "CreateOrOverwrite"

    [[generation.rules]]
    name = "capability-matrix"
    query = { file = "queries/capabilities.rq" }
    template = { file = "templates/capability_matrix.md.tmpl" }
    output_file = "generated/fortune5/ggen-capabilities/{{ capability_id }}.md"
    skip_empty = true
    mode = "CreateOrOverwrite"

    [[generation.rules]]
    name = "release-matrix"
    query = { file = "queries/release_matrix.rq" }
    template = { file = "templates/release_matrix.md.tmpl" }
    output_file = "generated/fortune5/ggen-release/{{ candidate_id }}.md"
    skip_empty = true
    mode = "CreateOrOverwrite"

    [[generation.rules]]
    name = "authority-matrix"
    query = { file = "queries/authority_matrix.rq" }
    template = { file = "templates/authority_matrix.md.tmpl" }
    output_file = "generated/fortune5/ggen-authority/authority.md"
    skip_empty = true
    mode = "CreateOrOverwrite"
    """
  end

  defp gate_semantic_subject do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      FILTER NOT EXISTS {
        f5:SemanticSubject a f5:AdmittedSemanticSubject ;
          f5:subjectSha256 ?hash ;
          f5:constructOnly true .
        FILTER(STRLEN(STR(?hash)) = 64)
      }
    }
    """
  end

  defp gate_candidate_identity do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      ?candidate a f5:Candidate .
      FILTER NOT EXISTS { ?candidate f5:candidateId ?candidate_id }
    }
    """
  end

  defp gate_candidate_topology do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      ?candidate a f5:Candidate .
      FILTER NOT EXISTS {
        ?candidate f5:deploymentTopology ?deployment ;
          f5:tenancyModel ?tenancy ;
          f5:executionMode ?execution ;
          f5:releaseStrategy ?release .
      }
    }
    """
  end

  defp gate_authority_boundary do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      FILTER NOT EXISTS {
        f5:AuthorityBoundary a f5:AuthorityContract ;
          f5:selectConstructDoSeparated true ;
          f5:brceOnlyDo true ;
          f5:ambientDo false .
      }
    }
    """
  end

  defp gate_capability_closure do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      ?capability a f5:Capability .
      FILTER NOT EXISTS {
        ?capability f5:capabilityId ?id ; f5:status ?status .
      }
    }
    """
  end

  defp gate_receipt_identity do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      ?candidate a f5:Candidate ; f5:candidateId ?candidate_id .
      FILTER(STRLEN(STR(?candidate_id)) != 64)
    }
    """
  end

  defp gate_no_ambient_do do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      f5:AuthorityBoundary f5:ambientDo true .
    }
    """
  end

  defp gate_runtime_evidence do
    """
    PREFIX f5: <#{@fortune5_ns}>
    ASK {
      ?capability a f5:Capability ; f5:status "ALIVE" .
      FILTER NOT EXISTS { ?capability f5:capabilityId ?id }
    }
    """
  end

  defp query_candidates do
    """
    PREFIX f5: <#{@fortune5_ns}>
    SELECT ?candidate_id ?score ?deployment ?tenancy ?consistency ?execution ?obda ?partition ?availability ?dr ?observability ?identity ?secret ?release ?migration ?network ?residency ?compliance ?cache ?isolation ?distribution ?control_plane WHERE {
      ?candidate a f5:Candidate ;
        f5:candidateId ?candidate_id ;
        f5:score ?score ;
        f5:deploymentTopology ?deployment ;
        f5:tenancyModel ?tenancy ;
        f5:consistencyModel ?consistency ;
        f5:executionMode ?execution ;
        f5:obdaTopology ?obda ;
        f5:partitionStrategy ?partition ;
        f5:availabilityModel ?availability ;
        f5:disasterRecovery ?dr ;
        f5:observability ?observability ;
        f5:workloadIdentity ?identity ;
        f5:secretProvider ?secret ;
        f5:releaseStrategy ?release ;
        f5:migrationStrategy ?migration ;
        f5:networkBoundary ?network ;
        f5:dataResidency ?residency ;
        f5:complianceProfile ?compliance ;
        f5:cacheStrategy ?cache ;
        f5:runtimeIsolation ?isolation ;
        f5:artifactDistribution ?distribution ;
        f5:controlPlane ?control_plane .
    }
    ORDER BY DESC(?score) ?candidate_id
    """
  end

  defp query_capabilities do
    """
    PREFIX f5: <#{@fortune5_ns}>
    SELECT ?capability_id ?status WHERE {
      ?capability a f5:Capability ;
        f5:capabilityId ?capability_id ;
        f5:status ?status .
    }
    ORDER BY ?capability_id
    """
  end

  defp query_release_matrix do
    """
    PREFIX f5: <#{@fortune5_ns}>
    SELECT ?candidate_id ?release ?deployment ?availability ?dr WHERE {
      ?candidate a f5:Candidate ;
        f5:candidateId ?candidate_id ;
        f5:releaseStrategy ?release ;
        f5:deploymentTopology ?deployment ;
        f5:availabilityModel ?availability ;
        f5:disasterRecovery ?dr .
    }
    ORDER BY ?candidate_id
    """
  end

  defp query_authority_matrix do
    """
    PREFIX f5: <#{@fortune5_ns}>
    SELECT ?separated ?brce ?ambient WHERE {
      f5:AuthorityBoundary a f5:AuthorityContract ;
        f5:selectConstructDoSeparated ?separated ;
        f5:brceOnlyDo ?brce ;
        f5:ambientDo ?ambient .
    }
    """
  end

  defp template_candidate_contract do
    """
    {
      "candidate_id": "{{ candidate_id }}",
      "score": "{{ score }}",
      "deployment_topology": "{{ deployment }}",
      "tenancy_model": "{{ tenancy }}",
      "consistency_model": "{{ consistency }}",
      "execution_mode": "{{ execution }}",
      "obda_topology": "{{ obda }}",
      "partition_strategy": "{{ partition }}",
      "availability_model": "{{ availability }}",
      "disaster_recovery": "{{ dr }}",
      "observability": "{{ observability }}",
      "workload_identity": "{{ identity }}",
      "secret_provider": "{{ secret }}",
      "release_strategy": "{{ release }}",
      "migration_strategy": "{{ migration }}",
      "network_boundary": "{{ network }}",
      "data_residency": "{{ residency }}",
      "compliance_profile": "{{ compliance }}",
      "cache_strategy": "{{ cache }}",
      "runtime_isolation": "{{ isolation }}",
      "artifact_distribution": "{{ distribution }}",
      "control_plane": "{{ control_plane }}"
    }
    """
  end

  defp template_capability_matrix do
    """
    # {{ capability_id }}

    Standing: **{{ status }}**

    This is a generated capability projection. `ALIVE` is valid only when the
    corresponding exact-subject evidence receipt has been observed.
    """
  end

  defp template_release_matrix do
    """
    # Release candidate {{ candidate_id }}

    - strategy: {{ release }}
    - deployment: {{ deployment }}
    - availability: {{ availability }}
    - disaster recovery: {{ dr }}

    Release projection does not grant release or cutover authority.
    """
  end

  defp template_authority_matrix do
    """
    # Authority matrix

    - SELECT/CONSTRUCT/DO separated: {{ separated }}
    - BRCE exclusive DO path: {{ brce }}
    - ambient DO authority: {{ ambient }}
    """
  end

  defp ttl_literal(value) when is_integer(value), do: "#{value}"
  defp ttl_literal(value) when is_float(value), do: "#{value}"
  defp ttl_literal(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp ttl_literal(value) when is_atom(value), do: ttl_literal(Atom.to_string(value))

  defp ttl_literal(value) when is_binary(value) do
    escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"") |> String.replace("\n", "\\n")
    "\"#{escaped}\""
  end

  defp json(term), do: encode_json(term, 0) <> "\n"

  defp encode_json(%_{} = struct, indent), do: encode_json(Map.from_struct(struct), indent)

  defp encode_json(map, indent) when is_map(map) do
    entries =
      map
      |> Enum.map(fn {key, value} -> {json_key(key), value} end)
      |> Enum.sort_by(&elem(&1, 0))

    if entries == [] do
      "{}"
    else
      pad = String.duplicate(" ", indent)
      child_pad = String.duplicate(" ", indent + 2)

      body =
        Enum.map_join(entries, ",\n", fn {key, value} ->
          child_pad <> Jason.encode!(key) <> ": " <> encode_json(value, indent + 2)
        end)

      "{\n" <> body <> "\n" <> pad <> "}"
    end
  end

  defp encode_json(list, indent) when is_list(list) do
    if list == [] do
      "[]"
    else
      pad = String.duplicate(" ", indent)
      child_pad = String.duplicate(" ", indent + 2)
      body = Enum.map_join(list, ",\n", &(child_pad <> encode_json(&1, indent + 2)))
      "[\n" <> body <> "\n" <> pad <> "]"
    end
  end

  defp encode_json(tuple, indent) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> encode_json(indent)
  defp encode_json(nil, _indent), do: "null"
  defp encode_json(true, _indent), do: "true"
  defp encode_json(false, _indent), do: "false"
  defp encode_json(value, _indent) when is_integer(value) or is_float(value), do: to_string(value)
  defp encode_json(value, _indent) when is_atom(value), do: Jason.encode!(Atom.to_string(value))
  defp encode_json(value, _indent) when is_binary(value), do: Jason.encode!(value)
  defp encode_json(value, _indent), do: Jason.encode!(inspect(value))

  defp json_key({left, right}), do: "#{json_key(left)}##{json_key(right)}"
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key), do: inspect(key)

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
