# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.CapabilityGraph do
  @moduledoc """
  Dependency-closed Fortune-5 capability graph.

  Capability presence is not evidence.  Every capability names the proof class
  required to promote it from `UNKNOWN`/`PARTIAL_ALIVE` to `ALIVE`, together
  with its authority class and dependencies.  The graph is pure data and may be
  projected by ggen into control matrices, runbooks, CI plans, or attestations.
  """

  defmodule Capability do
    @moduledoc "One production capability and its admission dependencies."
    @enforce_keys [:id, :domain, :proof, :authority]
    defstruct [
      :id,
      :domain,
      :proof,
      :authority,
      :criticality,
      :description,
      requires: [],
      tags: [],
      metadata: %{}
    ]

    @type t :: %__MODULE__{
            id: atom(),
            domain: atom(),
            proof: atom(),
            authority: atom(),
            criticality: atom(),
            description: String.t() | nil,
            requires: [atom()],
            tags: [atom()],
            metadata: map()
          }
  end

  defmodule Observation do
    @moduledoc "Evidence attached to one capability."
    @enforce_keys [:capability, :status]
    defstruct [
      :capability,
      :status,
      :proof,
      :receipt_sha256,
      :subject_sha256,
      :environment_sha256,
      :observed_at,
      details: %{}
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Admission do
    @moduledoc "Evidence-bounded capability admission result."
    defstruct [
      :status,
      :standing,
      :graph_sha256,
      :receipt_sha256,
      requested: [],
      closure: [],
      alive: [],
      partial_alive: [],
      unknown: [],
      blocked: [],
      unsupported: [],
      refused: [],
      evidence_plan: []
    ]

    @type t :: %__MODULE__{}
  end

  @doc "Canonical capability catalog."
  @spec catalog() :: [Capability.t()]
  def catalog do
    [
      # Semantic compiler spine
      cap(:ontology_profile_ingestion, :semantic_core, :unit_and_parser, :select, :critical,
        "RDF/OWL application-profile input can be parsed into the admission boundary"
      ),
      cap(:shacl_operational_closure, :semantic_core, :unit_and_parser, :select, :critical,
        "SHACL closes the operational facts required for deterministic projection",
        [:ontology_profile_ingestion]
      ),
      cap(:typed_semantic_admission, :semantic_core, :unit, :select, :critical,
        "ambiguous or unsupported semantics fail closed with typed refusals",
        [:shacl_operational_closure]
      ),
      cap(:canonical_semantic_ir, :semantic_core, :unit, :construct, :critical,
        "all admitted semantic inputs converge on deterministic SemanticIR",
        [:typed_semantic_admission]
      ),
      cap(:canonical_mapping_ir, :semantic_core, :unit, :construct, :critical,
        "Ash-first and ontology-first paths converge on Mapping.Bundle",
        [:canonical_semantic_ir]
      ),
      cap(:semantic_identity_integrity, :semantic_core, :falsifier, :select, :critical,
        "RDF identity is explicit and stable across relational and Ash projections",
        [:canonical_mapping_ir]
      ),
      cap(:loss_aware_datatypes, :semantic_core, :falsifier, :select, :critical,
        "unsupported datatypes refuse instead of silently becoming strings",
        [:canonical_mapping_ir]
      ),
      cap(:relationship_integrity, :semantic_core, :falsifier, :select, :critical,
        "semantic relationships survive as admitted reference mappings and joins",
        [:canonical_mapping_ir]
      ),
      cap(:graph_map_integrity, :semantic_core, :unit, :select, :high,
        "named graph placement remains deterministic and standards-valid",
        [:canonical_mapping_ir]
      ),
      cap(:deterministic_compilation_identity, :semantic_core, :two_pass, :construct, :critical,
        "same admitted subject manufactures byte-identical deterministic projections",
        [:canonical_semantic_ir, :canonical_mapping_ir]
      ),
      cap(:r2rml_projection, :semantic_projection, :rdf_parser, :construct, :critical,
        "Mapping.Bundle renders standards-valid R2RML",
        [:canonical_mapping_ir, :relationship_integrity, :loss_aware_datatypes]
      ),
      cap(:shacl_projection, :semantic_projection, :rdf_parser, :construct, :critical,
        "admitted operational shape is rendered deterministically",
        [:canonical_semantic_ir]
      ),
      cap(:ash_projection, :semantic_projection, :compile, :construct, :high,
        "ontology-first admission can manufacture ordinary Ash resources",
        [:canonical_semantic_ir]
      ),
      cap(:postgres_projection, :semantic_projection, :integration, :construct, :high,
        "semantic model can manufacture lawful relational DDL without applying it",
        [:canonical_semantic_ir]
      ),

      # ggen manufacturing
      cap(:ash_emitted_ttl_bundle, :ggen, :two_pass, :construct, :critical,
        "Ash resources emit ontology/SHACL/R2RML TTL without static duplicate source files",
        [:canonical_mapping_ir, :r2rml_projection, :shacl_projection]
      ),
      cap(:ggen_pack_contract, :ggen, :static_validation, :construct, :critical,
        "pack metadata, ontology imports, gates, queries and templates are explicit",
        [:ash_emitted_ttl_bundle]
      ),
      cap(:ggen_fail_closed_gates, :ggen, :ggen_execution, :construct, :critical,
        "generation gates reject missing or contradictory semantic facts before writes",
        [:ggen_pack_contract]
      ),
      cap(:ggen_query_projection, :ggen, :ggen_execution, :construct, :high,
        "SPARQL queries manufacture template-ready data without hidden semantic inference",
        [:ggen_fail_closed_gates]
      ),
      cap(:ggen_template_projection, :ggen, :ggen_execution, :construct, :high,
        "templates echo admitted query data and do not invent semantic facts",
        [:ggen_query_projection]
      ),
      cap(:ggen_atomic_publication_plan, :ggen, :integration, :construct, :critical,
        "all output paths and hashes are known before filesystem actuation",
        [:ggen_template_projection, :deterministic_compilation_identity]
      ),
      cap(:ggen_two_pass_determinism, :ggen, :two_pass, :construct, :critical,
        "two ggen runs over identical admitted inputs are byte-identical",
        [:ggen_atomic_publication_plan]
      ),
      cap(:ggen_replay_receipt, :ggen, :replay, :construct, :critical,
        "a manufacture can be reproduced from exact source, pack, toolchain and config identity",
        [:ggen_two_pass_determinism]
      ),

      # Query/OBDA
      cap(:sparql_language_admission, :obda, :unit, :select, :high,
        "SPARQL syntax is admitted before an execution topology is selected",
        [:canonical_mapping_ir]
      ),
      cap(:local_rdf_execution, :obda, :integration, :read, :medium,
        "bounded local RDF execution is available as one query topology",
        [:sparql_language_admission]
      ),
      cap(:sparql_protocol_execution, :obda, :external_observation, :read, :critical,
        "SPARQL protocol execution is observed against a real endpoint",
        [:sparql_language_admission]
      ),
      cap(:ontop_cli_execution, :obda, :external_observation, :read, :high,
        "official Ontop CLI executes generated mapping against PostgreSQL",
        [:r2rml_projection, :postgres_projection]
      ),
      cap(:bounded_external_execution, :obda, :falsifier, :read, :critical,
        "external queries are bounded by timeout, rows and bytes",
        [:sparql_protocol_execution]
      ),
      cap(:multi_engine_differential, :obda, :external_observation, :read, :critical,
        "same admitted query is compared across independent execution topologies",
        [:local_rdf_execution, :sparql_protocol_execution, :ontop_cli_execution]
      ),
      cap(:sql_sparql_parity, :obda, :external_observation, :read, :critical,
        "normalized SQL and SPARQL observations agree for the exact subject",
        [:ontop_cli_execution, :bounded_external_execution]
      ),
      cap(:legacy_control_parity, :obda, :external_observation, :read, :high,
        "candidate relational graph agrees with retained legacy control corpus",
        [:sql_sparql_parity]
      ),

      # Scale and performance
      cap(:horizontal_scaling, :scale, :stress, :platform, :critical,
        "work is horizontally distributable without semantic identity drift",
        [:deterministic_compilation_identity]
      ),
      cap(:partitioned_execution, :scale, :stress, :platform, :critical,
        "tenant/class/geography partitioning preserves semantic boundaries",
        [:horizontal_scaling]
      ),
      cap(:backpressure, :scale, :stress, :platform, :critical,
        "bounded queues reject or shed load rather than growing without bound",
        [:horizontal_scaling]
      ),
      cap(:million_concurrent_operations, :scale, :stress_1m, :platform, :critical,
        "one-million concurrent operation target is observed, not inferred",
        [:partitioned_execution, :backpressure, :fault_isolation]
      ),
      cap(:latency_slo, :scale, :benchmark, :platform, :critical,
        "p95/p99 latency and queue bounds are observed under admitted workload",
        [:backpressure, :observability_metrics]
      ),
      cap(:capacity_model, :scale, :benchmark, :platform, :high,
        "capacity planning binds throughput, concurrency, memory and external engine limits",
        [:latency_slo]
      ),

      # Tenancy and residency
      cap(:tenant_context_propagation, :tenancy, :integration, :runtime, :critical,
        "tenant identity follows semantic compilation and runtime observations",
        [:canonical_mapping_ir]
      ),
      cap(:tenant_data_isolation, :tenancy, :falsifier, :runtime, :critical,
        "cross-tenant reads/writes are mechanically refused",
        [:tenant_context_propagation]
      ),
      cap(:tenant_resource_quotas, :tenancy, :stress, :platform, :high,
        "per-tenant quotas prevent noisy-neighbor collapse",
        [:tenant_context_propagation, :backpressure]
      ),
      cap(:residency_routing, :tenancy, :integration, :platform, :critical,
        "country/region/sovereign placement is explicit and fail closed",
        [:tenant_context_propagation]
      ),
      cap(:cellular_fault_containment, :tenancy, :chaos, :platform, :critical,
        "cell failure does not collapse unrelated tenant partitions",
        [:partitioned_execution, :tenant_data_isolation]
      ),

      # Resilience
      cap(:otp_supervision, :resilience, :integration, :runtime, :high,
        "runtime processes have explicit restart/isolation strategy"
      ),
      cap(:fault_isolation, :resilience, :chaos, :runtime, :critical,
        "one failed worker/engine/cell does not imply graph-wide failure",
        [:otp_supervision]
      ),
      cap(:regional_failover, :resilience, :chaos, :platform, :critical,
        "regional loss is observed with bounded recovery",
        [:fault_isolation, :artifact_replication]
      ),
      cap(:disaster_recovery, :resilience, :dr_drill, :platform, :critical,
        "RPO/RTO are proven by restoration or failover drill",
        [:regional_failover, :receipt_replay]
      ),
      cap(:deterministic_recovery, :resilience, :replay, :runtime, :critical,
        "recovery is bound to exact input/toolchain/receipt identities",
        [:receipt_replay]
      ),
      cap(:chaos_corpus, :resilience, :chaos, :verification, :high,
        "known failure modes have permanent executable falsifiers",
        [:fault_isolation]
      ),

      # Observability
      cap(:observability_events, :observability, :unit, :construct, :critical,
        "admit/construct/do/receipt/replay/refusal events have stable schemas"
      ),
      cap(:observability_metrics, :observability, :integration, :runtime, :critical,
        "latency, queue, refusal, cardinality and external-engine metrics are emitted",
        [:observability_events]
      ),
      cap(:trace_context, :observability, :integration, :runtime, :critical,
        "trace identity crosses compiler, ggen, OBDA and runtime boundaries",
        [:observability_events]
      ),
      cap(:receipt_trace_correlation, :observability, :integration, :runtime, :critical,
        "every receipted actuation can be correlated to semantic and trace identity",
        [:trace_context, :receipt_replay]
      ),
      cap(:bounded_metric_cardinality, :observability, :falsifier, :runtime, :high,
        "telemetry labels cannot explode on raw tenant/IRI/query values",
        [:observability_metrics]
      ),

      # Security and authority
      cap(:least_privilege, :security, :policy_verifier, :security, :critical,
        "components receive only the capabilities required for their role"
      ),
      cap(:no_ambient_execution_authority, :security, :falsifier, :security, :critical,
        "raw input, templates, model output and hooks cannot directly actuate",
        [:least_privilege]
      ),
      cap(:workload_identity, :security, :integration, :security, :critical,
        "machine-to-machine identity is short lived and attestable",
        [:least_privilege]
      ),
      cap(:secret_externalization, :security, :integration, :security, :critical,
        "secrets are not embedded in generated source, TTL or receipts",
        [:least_privilege]
      ),
      cap(:network_zero_trust, :security, :integration, :security, :high,
        "service-to-service policy is authenticated and explicitly authorized",
        [:workload_identity]
      ),
      cap(:brce_do_authority, :security, :actuation_receipt, :do, :critical,
        "BRCE is the exclusive DO path and every mutation has a receipt",
        [:no_ambient_execution_authority, :receipt_trace_correlation]
      ),
      cap(:idempotency_keys, :security, :integration, :do, :critical,
        "retryable mutation paths carry stable idempotency identity",
        [:brce_do_authority]
      ),
      cap(:cutover_authority, :security, :authority_receipt, :do, :critical,
        "production cutover requires organizational authority independent of technical parity",
        [:brce_do_authority, :sql_sparql_parity]
      ),

      # Supply chain/release
      cap(:sbom, :supply_chain, :artifact, :release, :critical,
        "release artifact carries a machine-readable software bill of materials"
      ),
      cap(:signed_artifacts, :supply_chain, :signature, :release, :critical,
        "release artifacts are cryptographically signed",
        [:sbom]
      ),
      cap(:provenance_attestation, :supply_chain, :attestation, :release, :critical,
        "build provenance binds source, toolchain, dependencies and artifact hashes",
        [:signed_artifacts]
      ),
      cap(:vulnerability_gate, :supply_chain, :security_scan, :release, :critical,
        "known vulnerability policy is evaluated before release authority",
        [:sbom]
      ),
      cap(:artifact_replication, :supply_chain, :external_observation, :release, :high,
        "signed artifacts are replicated to admitted failure/residency domains",
        [:signed_artifacts]
      ),
      cap(:progressive_delivery, :release, :integration, :release, :high,
        "canary/blue-green/cell rollout is bounded by observation gates",
        [:observability_metrics, :signed_artifacts]
      ),
      cap(:rollback_plan, :release, :replay, :release, :critical,
        "release has explicit rollback and semantic/schema compatibility bounds",
        [:progressive_delivery]
      ),
      cap(:release_receipt, :release, :external_observation, :release, :critical,
        "released artifact identity is bound to exact verification evidence",
        [:provenance_attestation, :vulnerability_gate, :rollback_plan]
      ),

      # Receipt/replay/governance
      cap(:receipt_identity, :governance, :unit, :construct, :critical,
        "receipt hash binds exact subject and evidence identity"
      ),
      cap(:receipt_replay, :governance, :replay, :construct, :critical,
        "receipt can drive deterministic replay without hidden ambient inputs",
        [:receipt_identity]
      ),
      cap(:evidence_standing_lattice, :governance, :unit, :select, :critical,
        "checkpoint proof cannot silently promote itself to subject-level ALIVE",
        [:receipt_identity]
      ),
      cap(:decision_log, :governance, :integration, :construct, :high,
        "irreversible selection records candidates, constraints, authority and consequence",
        [:evidence_standing_lattice]
      ),
      cap(:change_drift_classification, :governance, :falsifier, :construct, :high,
        "semantic changes are classified before regeneration or deployment",
        [:deterministic_compilation_identity, :decision_log]
      ),
      cap(:policy_as_data, :governance, :unit, :select, :high,
        "governance rules are inspectable data and do not gain ambient DO authority",
        [:decision_log]
      ),

      # Compliance evidence
      cap(:control_mapping, :compliance, :static_validation, :governance, :high,
        "technical capabilities can be mapped to external control identifiers without claiming certification",
        [:policy_as_data]
      ),
      cap(:evidence_export, :compliance, :artifact, :governance, :high,
        "receipts and observations can be exported as bounded machine-readable evidence",
        [:control_mapping, :receipt_identity]
      ),
      cap(:audit_replay, :compliance, :replay, :governance, :critical,
        "auditor can replay exact bounded evidence without privileged production mutation",
        [:evidence_export, :receipt_replay]
      ),

      # Operator surfaces
      cap(:health_contract, :operations, :integration, :runtime, :high,
        "health distinguishes process liveness, dependency readiness and subject standing",
        [:observability_metrics]
      ),
      cap(:graceful_degradation, :operations, :chaos, :runtime, :critical,
        "loss of one optional query topology degrades capability rather than corrupting semantics",
        [:fault_isolation, :health_contract]
      ),
      cap(:runbook_generation, :operations, :ggen_execution, :construct, :high,
        "operator runbooks are generated from the same admitted production contract",
        [:ggen_template_projection, :decision_log]
      ),
      cap(:machine_readable_verifier_report, :operations, :verification, :construct, :critical,
        "verification emits a stable machine-readable report consumed by release admission",
        [:evidence_standing_lattice]
      )
    ]
  end

  @doc "Return a capability by id."
  def get(id) do
    case Enum.find(catalog(), &(&1.id == id)) do
      nil -> {:error, %{code: :UNKNOWN_CAPABILITY, subject: id}}
      capability -> {:ok, capability}
    end
  end

  @doc "Dependency-close a requested capability set."
  def closure(requested) do
    index = index()

    requested
    |> List.wrap()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn id, {:ok, acc} ->
      case close(id, index, acc, MapSet.new()) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, set} -> {:ok, topological(MapSet.to_list(set), index)}
      other -> other
    end
  end

  @doc "Validate dependency references and cycles in the canonical catalog."
  def validate_catalog do
    ids = MapSet.new(Enum.map(catalog(), & &1.id))

    missing =
      catalog()
      |> Enum.flat_map(fn capability ->
        capability.requires
        |> Enum.reject(&MapSet.member?(ids, &1))
        |> Enum.map(&{capability.id, &1})
      end)

    cycles =
      catalog()
      |> Enum.map(& &1.id)
      |> Enum.flat_map(fn id ->
        case close(id, index(), MapSet.new(), MapSet.new()) do
          {:ok, _} -> []
          {:error, %{code: :CAPABILITY_DEPENDENCY_CYCLE} = error} -> [error]
          {:error, _} -> []
        end
      end)

    cond do
      missing != [] -> {:error, %{code: :MISSING_CAPABILITY_DEPENDENCY, edges: missing}}
      cycles != [] -> {:error, %{code: :CAPABILITY_DEPENDENCY_CYCLE, cycles: cycles}}
      true -> :ok
    end
  end

  @doc "Admit requested capabilities against exact observations."
  def admit(requested, observations \\ []) do
    with :ok <- validate_catalog(),
         {:ok, closed} <- closure(requested) do
      observation_index = observation_index(observations)
      capability_index = index()

      classified =
        Enum.map(closed, fn id ->
          capability = Map.fetch!(capability_index, id)
          observation = Map.get(observation_index, id)
          {id, classify(capability, observation)}
        end)

      alive = ids_with(classified, :ALIVE)
      partial = ids_with(classified, :PARTIAL_ALIVE)
      unknown = ids_with(classified, :UNKNOWN)
      blocked = ids_with(classified, :BLOCKED)
      unsupported = ids_with(classified, :UNSUPPORTED)
      refused = ids_with(classified, :REFUSED)

      status =
        cond do
          refused != [] -> :REFUSED
          blocked != [] -> :BLOCKED
          unsupported != [] -> :UNSUPPORTED
          unknown != [] or partial != [] -> :PARTIAL_ALIVE
          true -> :ALIVE
        end

      standing =
        if status == :ALIVE,
          do: :requested_capability_closure_alive,
          else: :capability_closure_incomplete

      plan = evidence_plan(closed, observation_index)

      base = %Admission{
        status: status,
        standing: standing,
        graph_sha256: graph_sha256(),
        requested: List.wrap(requested),
        closure: closed,
        alive: alive,
        partial_alive: partial,
        unknown: unknown,
        blocked: blocked,
        unsupported: unsupported,
        refused: refused,
        evidence_plan: plan
      }

      %{base | receipt_sha256: sha256(Map.from_struct(base))}
    end
  end

  @doc "Build the cheapest dependency-ordered evidence plan for incomplete capabilities."
  def evidence_plan(closed, observation_index \\ %{}) do
    capability_index = index()

    closed
    |> Enum.reject(fn id ->
      case Map.get(observation_index, id) do
        %Observation{status: :ALIVE} -> true
        %{status: :ALIVE} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn id ->
      capability = Map.fetch!(capability_index, id)

      %{
        capability: id,
        proof: capability.proof,
        authority: capability.authority,
        criticality: capability.criticality,
        requires: capability.requires,
        command_class: command_class(capability.proof)
      }
    end)
  end

  @doc "Group capabilities by domain for ggen matrices and runbooks."
  def domain_matrix do
    catalog()
    |> Enum.group_by(& &1.domain)
    |> Map.new(fn {domain, capabilities} ->
      {domain,
       capabilities
       |> Enum.sort_by(& &1.id)
       |> Enum.map(fn capability ->
         %{
           id: capability.id,
           proof: capability.proof,
           authority: capability.authority,
           criticality: capability.criticality,
           requires: capability.requires
         }
       end)}
    end)
  end

  @doc "Stable graph identity."
  def graph_sha256, do: sha256(catalog())

  def sha256(term) do
    term
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  defp cap(id, domain, proof, authority, criticality, description, requires \\ []) do
    %Capability{
      id: id,
      domain: domain,
      proof: proof,
      authority: authority,
      criticality: criticality,
      description: description,
      requires: requires,
      tags: Enum.uniq([domain, proof, authority, criticality])
    }
  end

  defp index, do: Map.new(catalog(), &{&1.id, &1})

  defp close(id, index, acc, visiting) do
    cond do
      MapSet.member?(acc, id) ->
        {:ok, acc}

      MapSet.member?(visiting, id) ->
        {:error, %{code: :CAPABILITY_DEPENDENCY_CYCLE, subject: id}}

      not Map.has_key?(index, id) ->
        {:error, %{code: :UNKNOWN_CAPABILITY, subject: id}}

      true ->
        capability = Map.fetch!(index, id)
        visiting = MapSet.put(visiting, id)

        Enum.reduce_while(capability.requires, {:ok, acc}, fn dependency, {:ok, nested_acc} ->
          case close(dependency, index, nested_acc, visiting) do
            {:ok, next} -> {:cont, {:ok, next}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, next} -> {:ok, MapSet.put(next, id)}
          other -> other
        end
    end
  end

  defp topological(ids, index) do
    set = MapSet.new(ids)
    do_topological(set, index, [])
  end

  defp do_topological(set, _index, acc) when map_size(set.map) == 0, do: Enum.reverse(acc)

  defp do_topological(set, index, acc) do
    emitted = MapSet.new(acc)

    ready =
      set
      |> MapSet.to_list()
      |> Enum.filter(fn id ->
        Map.fetch!(index, id).requires
        |> Enum.all?(&MapSet.member?(emitted, &1))
      end)
      |> Enum.sort()

    case ready do
      [] -> Enum.reverse(acc) ++ Enum.sort(MapSet.to_list(set))
      _ -> do_topological(Enum.reduce(ready, set, &MapSet.delete(&2, &1)), index, Enum.reverse(ready) ++ acc)
    end
  end

  defp observation_index(observations) when is_map(observations), do: observations

  defp observation_index(observations) do
    Map.new(observations, fn
      %Observation{capability: id} = observation -> {id, observation}
      %{capability: id} = observation -> {id, observation}
      {id, observation} -> {id, observation}
    end)
  end

  defp classify(_capability, nil), do: :UNKNOWN

  defp classify(capability, %Observation{} = observation) do
    classify_observation(capability, Map.from_struct(observation))
  end

  defp classify(capability, observation) when is_map(observation) do
    classify_observation(capability, observation)
  end

  defp classify(_capability, _observation), do: :UNKNOWN

  defp classify_observation(capability, observation) do
    status = Map.get(observation, :status, Map.get(observation, "status", :UNKNOWN))
    proof = Map.get(observation, :proof, Map.get(observation, "proof"))
    receipt = Map.get(observation, :receipt_sha256, Map.get(observation, "receipt_sha256"))

    cond do
      status in [:REFUSED, "REFUSED"] -> :REFUSED
      status in [:UNSUPPORTED, "UNSUPPORTED"] -> :UNSUPPORTED
      status in [:BLOCKED, "BLOCKED"] -> :BLOCKED
      status in [:ALIVE, "ALIVE"] and proof == capability.proof and present?(receipt) -> :ALIVE
      status in [:ALIVE, "ALIVE", :PARTIAL_ALIVE, "PARTIAL_ALIVE"] -> :PARTIAL_ALIVE
      true -> :UNKNOWN
    end
  end

  defp ids_with(classified, status) do
    classified
    |> Enum.filter(fn {_id, observed} -> observed == status end)
    |> Enum.map(&elem(&1, 0))
  end

  defp command_class(:unit), do: :mix_test_focused
  defp command_class(:unit_and_parser), do: :mix_test_plus_rdf_parse
  defp command_class(:compile), do: :mix_compile_warnings_as_errors
  defp command_class(:static_validation), do: :static_contract_gate
  defp command_class(:rdf_parser), do: :independent_rdf_parser
  defp command_class(:two_pass), do: :deterministic_two_pass
  defp command_class(:ggen_execution), do: :real_ggen_sync_run
  defp command_class(:integration), do: :integration_test
  defp command_class(:external_observation), do: :real_external_boundary
  defp command_class(:falsifier), do: :negative_test
  defp command_class(:stress), do: :stress_test
  defp command_class(:stress_1m), do: :million_concurrency_stress
  defp command_class(:benchmark), do: :benchmark
  defp command_class(:chaos), do: :chaos_test
  defp command_class(:dr_drill), do: :disaster_recovery_drill
  defp command_class(:replay), do: :deterministic_replay
  defp command_class(:policy_verifier), do: :policy_verification
  defp command_class(:actuation_receipt), do: :brce_actuation
  defp command_class(:authority_receipt), do: :organizational_authority
  defp command_class(:artifact), do: :artifact_generation
  defp command_class(:signature), do: :signature_verification
  defp command_class(:attestation), do: :provenance_verification
  defp command_class(:security_scan), do: :security_scan
  defp command_class(:verification), do: :machine_readable_verifier
  defp command_class(other), do: other

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
