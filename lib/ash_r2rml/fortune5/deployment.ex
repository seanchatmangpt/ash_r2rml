# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.Deployment do
  @moduledoc """
  Reversible deployment composition for admitted Fortune-5 DfCM candidates.

  A deployment plan is CONSTRUCT-only. It describes cells, process roles,
  permissions, health semantics, disruption policy, autoscaling envelopes and
  scheduler projections without invoking a cloud API, Kubernetes, a database,
  or ggen. ggen remains the materialization authority.
  """

  alias AshR2RML.Fortune5.DfCM

  defmodule Component do
    @moduledoc "One supervised production component role."
    @enforce_keys [:name, :role, :authority]
    defstruct [
      :name,
      :role,
      :authority,
      :image,
      :replicas,
      :min_replicas,
      :max_replicas,
      :cpu_request_millis,
      :memory_request_mib,
      :cpu_limit_millis,
      :memory_limit_mib,
      :health_path,
      :readiness_path,
      :service_port,
      capabilities: [],
      dependencies: [],
      environment: %{},
      secret_refs: [],
      labels: %{}
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Cell do
    @moduledoc "One failure-isolated deployment cell."
    @enforce_keys [:id, :region]
    defstruct [
      :id,
      :region,
      :ordinal,
      :residency_class,
      :failure_domain,
      :capacity_weight,
      :environment_sha256,
      components: [],
      labels: %{}
    ]

    @type t :: %__MODULE__{}
  end

  defmodule Plan do
    @moduledoc "Platform-neutral deployment construction."
    @enforce_keys [:candidate_id]
    defstruct [
      :candidate_id,
      :plan_sha256,
      :status,
      :standing,
      :topology,
      :release_strategy,
      :artifact_distribution,
      :network_boundary,
      :workload_identity,
      :secret_provider,
      regions: [],
      cells: [],
      invariants: [],
      refusals: []
    ]

    @type t :: %__MODULE__{}
  end

  @default_regions ["region-a", "region-b", "region-c", "region-d"]

  @doc "Construct one platform-neutral deployment plan from an admitted candidate."
  @spec plan(DfCM.Candidate.t(), keyword()) :: {:ok, Plan.t()} | {:error, Plan.t()}
  def plan(%DfCM.Candidate{refusals: []} = candidate, opts \\ []) do
    assignment = candidate.assignment
    requested_regions = Keyword.get(opts, :regions, @default_regions)
    desired_region_count = region_count(assignment.deployment_topology)
    regions = requested_regions |> Enum.uniq() |> Enum.take(desired_region_count)
    cells_per_region = cells_per_region(assignment.deployment_topology, Keyword.get(opts, :cells_per_region, 3))
    image = Keyword.get(opts, :image, "ash-r2rml@sha256:UNBOUND")

    cells =
      for {region, region_index} <- Enum.with_index(regions, 1),
          ordinal <- 1..cells_per_region do
        id = cell_id(region, ordinal)

        %Cell{
          id: id,
          region: region,
          ordinal: ordinal,
          residency_class: assignment.data_residency,
          failure_domain: failure_domain(assignment, region, ordinal),
          capacity_weight: capacity_weight(assignment, region_index),
          environment_sha256: sha256({candidate.id, region, ordinal, :environment}),
          components: components(candidate, id, image),
          labels: %{
            topology: assignment.deployment_topology,
            region: region,
            cell: id,
            candidate_sha256: candidate.id
          }
        }
      end

    base = %Plan{
      candidate_id: candidate.id,
      status: :PARTIAL_ALIVE,
      standing: :deployment_plan_constructed_not_actuated,
      topology: assignment.deployment_topology,
      release_strategy: assignment.release_strategy,
      artifact_distribution: assignment.artifact_distribution,
      network_boundary: assignment.network_boundary,
      workload_identity: assignment.workload_identity,
      secret_provider: assignment.secret_provider,
      regions: regions,
      cells: cells,
      invariants: invariants(candidate),
      refusals: []
    }

    expected_regions = region_count(assignment.deployment_topology)

    case validate(base, expected_regions) do
      :ok ->
        {:ok, %{base | plan_sha256: sha256(Map.from_struct(base))}}

      {:error, refusals} ->
        {:error,
         %{
           base
           | status: :REFUSED,
             standing: :deployment_plan_refused,
             refusals: refusals,
             plan_sha256: sha256(refusals)
         }}
    end
  end

  def plan(%DfCM.Candidate{} = candidate, _opts) do
    {:error,
     %Plan{
       candidate_id: candidate.id,
       status: :REFUSED,
       standing: :deployment_plan_refused,
       refusals: [%{code: :REFUSED_DFCM_CANDIDATE_NOT_ADMITTED, subject: candidate.id}],
       plan_sha256: sha256(candidate.refusals)
     }}
  end

  @doc "Validate deployment authority, secret, identity and topology invariants."
  def validate(%Plan{} = plan), do: validate(plan, region_count(plan.topology))

  defp validate(%Plan{} = plan, expected_region_count) do
    components = Enum.flat_map(plan.cells, & &1.components)

    do_violations =
      components
      |> Enum.filter(fn component ->
        :perform_bounded_do in component.capabilities and component.role != :brce_actuator
      end)
      |> Enum.map(&%{code: :REFUSED_COMPONENT_AMBIENT_DO, subject: &1.name})

    secret_violations =
      Enum.flat_map(components, fn component ->
        component.environment
        |> Enum.filter(fn {key, _value} -> secret_key?(key) end)
        |> Enum.map(fn {key, _value} ->
          %{
            code: :REFUSED_PLAINTEXT_SECRET_ENV,
            subject: component.name,
            evidence: %{key: key}
          }
        end)
      end)

    region_violations =
      if length(plan.regions) == expected_region_count do
        []
      else
        [
          %{
            code: :REFUSED_DEPLOYMENT_REGION_CLOSURE,
            subject: plan.candidate_id,
            evidence: %{expected: expected_region_count, actual: length(plan.regions)}
          }
        ]
      end

    cell_ids = Enum.map(plan.cells, & &1.id)

    duplicate_violations =
      cell_ids
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, count} ->
        %{code: :REFUSED_DUPLICATE_CELL_ID, subject: id, evidence: %{count: count}}
      end)

    brce_violations =
      components
      |> Enum.filter(&(&1.role == :brce_actuator))
      |> Enum.flat_map(fn component ->
        if component.authority == :do and :perform_bounded_do in component.capabilities do
          []
        else
          [%{code: :REFUSED_BRCE_AUTHORITY_CLASS, subject: component.name}]
        end
      end)

    identity_violations =
      if plan.workload_identity in [:workload_identity, :spiffe, :oidc_federated] do
        []
      else
        [%{code: :REFUSED_WORKLOAD_IDENTITY, subject: plan.workload_identity}]
      end

    refusals =
      do_violations ++ secret_violations ++ region_violations ++ duplicate_violations ++
        brce_violations ++ identity_violations

    if refusals == [], do: :ok, else: {:error, refusals}
  end

  @doc "Project a plan to Kubernetes-compatible JSON objects without applying them."
  def kubernetes(%Plan{} = plan, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "ash-r2rml")

    component_objects =
      Enum.flat_map(plan.cells, fn cell ->
        Enum.flat_map(cell.components, fn component ->
          [
            deployment_object(namespace, plan, cell, component),
            service_object(namespace, plan, cell, component),
            pdb_object(namespace, plan, cell, component),
            hpa_object(namespace, plan, cell, component)
          ]
        end)
      end)

    shared = [
      namespace_object(namespace, plan),
      service_account_object(namespace, plan),
      network_default_deny_object(namespace, plan),
      network_dns_egress_object(namespace, plan),
      config_map_object(namespace, plan)
    ]

    shared ++ component_objects
  end

  @doc "Project a plan to scheduler-neutral workload declarations."
  def scheduler(%Plan{} = plan) do
    %{
      version: "fortune5-scheduler-plan-v1",
      candidate_id: plan.candidate_id,
      topology: plan.topology,
      regions: plan.regions,
      workloads:
        Enum.flat_map(plan.cells, fn cell ->
          Enum.map(cell.components, fn component ->
            %{
              id: "#{cell.id}/#{component.name}",
              region: cell.region,
              cell: cell.id,
              role: component.role,
              authority: component.authority,
              image: component.image,
              replicas: component.replicas,
              autoscaling: %{min: component.min_replicas, max: component.max_replicas},
              resources: %{
                cpu_request_millis: component.cpu_request_millis,
                memory_request_mib: component.memory_request_mib,
                cpu_limit_millis: component.cpu_limit_millis,
                memory_limit_mib: component.memory_limit_mib
              },
              dependencies: component.dependencies,
              capabilities: component.capabilities,
              secret_refs: component.secret_refs,
              environment: component.environment
            }
          end)
        end)
    }
  end

  @doc "Return an environment-neutral progressive rollout matrix."
  def rollout_matrix(%Plan{} = plan) do
    cell_ids = Enum.map(plan.cells, & &1.id)

    phases =
      case plan.release_strategy do
        :rolling ->
          [%{name: "rolling", cells: cell_ids, traffic_percent: 100}]

        :blue_green ->
          [
            %{name: "green-shadow", cells: cell_ids, traffic_percent: 0},
            %{name: "green-cutover", cells: cell_ids, traffic_percent: 100, authority_required?: true}
          ]

        :canary ->
          canary_phases(cell_ids)

        :cell_progressive ->
          cell_progressive_phases(cell_ids)
      end

    %{
      candidate_id: plan.candidate_id,
      strategy: plan.release_strategy,
      phases: phases,
      abort_on: [
        :semantic_parity_failure,
        :slo_burn,
        :typed_refusal_regression,
        :replay_mismatch
      ],
      rebuild_between_phases?: false,
      immutable_artifact_required?: true
    }
  end

  defp components(candidate, cell_id, image) do
    assignment = candidate.assignment

    base = [
      component(:semantic_runtime, :query_verifier, :read, image, cell_id,
        [:read_mapping, :execute_bounded_query, :emit_verification_receipt],
        [:postgres, :obda]
      ),
      component(:compiler, :compiler, :construct, image, cell_id,
        [
          :read_admitted_semantics,
          :construct_mapping,
          :construct_projection,
          :emit_construct_receipt
        ],
        []
      ),
      component(:ggen_manufacturer, :ggen_manufacturer, :construct, image, cell_id,
        [
          :read_construct_plan,
          :materialize_projection,
          :hash_staged_artifact,
          :emit_manufacture_receipt
        ],
        []
      ),
      component(:verifier, :release_verifier, :verification, image, cell_id,
        [:read_artifact, :read_evidence, :evaluate_release_gate],
        [:postgres, :obda]
      )
    ]

    if assignment.execution_mode == :receipted_write_runtime do
      base ++
        [
          component(:brce_actuator, :brce_actuator, :do, image, cell_id,
            [:consume_admitted_do_intent, :perform_bounded_do, :emit_do_receipt],
            [:postgres]
          )
        ]
    else
      base
    end
  end

  defp component(name, role, authority, image, cell_id, capabilities, dependencies) do
    resources = resource_class(role)

    %Component{
      name: name,
      role: role,
      authority: authority,
      image: image,
      replicas: resources.replicas,
      min_replicas: resources.min,
      max_replicas: resources.max,
      cpu_request_millis: resources.cpu_request,
      memory_request_mib: resources.memory_request,
      cpu_limit_millis: resources.cpu_limit,
      memory_limit_mib: resources.memory_limit,
      health_path: "/health/live",
      readiness_path: "/health/ready",
      service_port: 4_000,
      capabilities: capabilities,
      dependencies: dependencies,
      environment: %{
        "ASH_R2RML_CELL" => cell_id,
        "ASH_R2RML_ROLE" => Atom.to_string(role),
        "ASH_R2RML_AUTHORITY" => Atom.to_string(authority)
      },
      secret_refs: secret_refs(role),
      labels: %{role: role, authority: authority, cell: cell_id}
    }
  end

  defp resource_class(:query_verifier),
    do: %{replicas: 3, min: 3, max: 500, cpu_request: 500, memory_request: 512, cpu_limit: 4_000, memory_limit: 4_096}

  defp resource_class(:compiler),
    do: %{replicas: 2, min: 2, max: 200, cpu_request: 1_000, memory_request: 1_024, cpu_limit: 8_000, memory_limit: 8_192}

  defp resource_class(:ggen_manufacturer),
    do: %{replicas: 2, min: 2, max: 100, cpu_request: 1_000, memory_request: 1_024, cpu_limit: 8_000, memory_limit: 8_192}

  defp resource_class(:release_verifier),
    do: %{replicas: 2, min: 2, max: 100, cpu_request: 500, memory_request: 512, cpu_limit: 4_000, memory_limit: 4_096}

  defp resource_class(:brce_actuator),
    do: %{replicas: 3, min: 3, max: 200, cpu_request: 500, memory_request: 512, cpu_limit: 4_000, memory_limit: 4_096}

  defp secret_refs(:query_verifier), do: ["postgres-readonly", "obda-readonly"]
  defp secret_refs(:brce_actuator), do: ["postgres-brce"]
  defp secret_refs(_role), do: []

  defp region_count(:single_region), do: 1
  defp region_count(:multi_region_active_passive), do: 2
  defp region_count(:multi_region_active_active), do: 2
  defp region_count(:cellular_multi_region), do: 3

  defp cells_per_region(:cellular_multi_region, requested), do: max(requested, 2)
  defp cells_per_region(_topology, _requested), do: 1

  defp failure_domain(assignment, region, ordinal) do
    if assignment.deployment_topology == :cellular_multi_region,
      do: "#{region}/cell-#{ordinal}",
      else: region
  end

  defp capacity_weight(assignment, region_index) do
    if assignment.deployment_topology == :multi_region_active_passive and region_index != 1,
      do: 0,
      else: 100
  end

  defp cell_id(region, ordinal), do: "#{region}-cell-#{ordinal}"

  defp invariants(candidate) do
    assignment = candidate.assignment

    [
      :immutable_artifact_digest,
      :no_plaintext_secrets,
      :workload_identity_required,
      :network_default_deny,
      :health_liveness_separate_from_readiness,
      :pod_disruption_budget,
      :topology_spread,
      :bounded_autoscaling,
      :observability_receipt_correlation,
      :brce_only_do,
      :no_cutover_authority_in_workload,
      {:network_boundary, assignment.network_boundary},
      {:secret_provider, assignment.secret_provider},
      {:workload_identity, assignment.workload_identity}
    ]
  end

  defp namespace_object(namespace, plan) do
    %{apiVersion: "v1", kind: "Namespace", metadata: %{name: namespace, labels: base_labels(plan)}}
  end

  defp service_account_object(namespace, plan) do
    %{
      apiVersion: "v1",
      kind: "ServiceAccount",
      metadata: %{name: "ash-r2rml", namespace: namespace, labels: base_labels(plan)},
      automountServiceAccountToken: false
    }
  end

  defp config_map_object(namespace, plan) do
    %{
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: %{
        name: "ash-r2rml-production-contract",
        namespace: namespace,
        labels: base_labels(plan)
      },
      data: %{
        "candidate_sha256" => plan.candidate_id,
        "topology" => Atom.to_string(plan.topology),
        "release_strategy" => Atom.to_string(plan.release_strategy),
        "network_boundary" => Atom.to_string(plan.network_boundary)
      }
    }
  end

  defp deployment_object(namespace, plan, cell, component) do
    labels = component_labels(plan, cell, component)

    %{
      apiVersion: "apps/v1",
      kind: "Deployment",
      metadata: %{name: kube_name(cell, component), namespace: namespace, labels: labels},
      spec: %{
        replicas: component.replicas,
        selector: %{matchLabels: selector_labels(cell, component)},
        strategy: deployment_strategy(plan.release_strategy),
        template: %{
          metadata: %{labels: labels},
          spec: %{
            serviceAccountName: "ash-r2rml",
            automountServiceAccountToken: false,
            terminationGracePeriodSeconds: 30,
            securityContext: %{runAsNonRoot: true, seccompProfile: %{type: "RuntimeDefault"}},
            topologySpreadConstraints: topology_spread(cell, component),
            containers: [container(component)]
          }
        }
      }
    }
  end

  defp service_object(namespace, plan, cell, component) do
    %{
      apiVersion: "v1",
      kind: "Service",
      metadata: %{
        name: kube_name(cell, component),
        namespace: namespace,
        labels: component_labels(plan, cell, component)
      },
      spec: %{
        type: "ClusterIP",
        selector: selector_labels(cell, component),
        ports: [
          %{
            name: "http",
            port: component.service_port,
            targetPort: component.service_port,
            protocol: "TCP"
          }
        ]
      }
    }
  end

  defp pdb_object(namespace, plan, cell, component) do
    %{
      apiVersion: "policy/v1",
      kind: "PodDisruptionBudget",
      metadata: %{
        name: kube_name(cell, component),
        namespace: namespace,
        labels: component_labels(plan, cell, component)
      },
      spec: %{
        minAvailable: if(component.replicas >= 3, do: 2, else: 1),
        selector: %{matchLabels: selector_labels(cell, component)}
      }
    }
  end

  defp hpa_object(namespace, plan, cell, component) do
    %{
      apiVersion: "autoscaling/v2",
      kind: "HorizontalPodAutoscaler",
      metadata: %{
        name: kube_name(cell, component),
        namespace: namespace,
        labels: component_labels(plan, cell, component)
      },
      spec: %{
        scaleTargetRef: %{
          apiVersion: "apps/v1",
          kind: "Deployment",
          name: kube_name(cell, component)
        },
        minReplicas: component.min_replicas,
        maxReplicas: component.max_replicas,
        behavior: %{
          scaleUp: %{
            stabilizationWindowSeconds: 30,
            policies: [%{type: "Percent", value: 100, periodSeconds: 60}]
          },
          scaleDown: %{
            stabilizationWindowSeconds: 300,
            policies: [%{type: "Percent", value: 25, periodSeconds: 60}]
          }
        },
        metrics: [
          %{
            type: "Resource",
            resource: %{
              name: "cpu",
              target: %{type: "Utilization", averageUtilization: 70}
            }
          }
        ]
      }
    }
  end

  defp network_default_deny_object(namespace, plan) do
    %{
      apiVersion: "networking.k8s.io/v1",
      kind: "NetworkPolicy",
      metadata: %{
        name: "ash-r2rml-default-deny",
        namespace: namespace,
        labels: base_labels(plan)
      },
      spec: %{podSelector: %{}, policyTypes: ["Ingress", "Egress"]}
    }
  end

  defp network_dns_egress_object(namespace, plan) do
    %{
      apiVersion: "networking.k8s.io/v1",
      kind: "NetworkPolicy",
      metadata: %{
        name: "ash-r2rml-dns-egress",
        namespace: namespace,
        labels: base_labels(plan)
      },
      spec: %{
        podSelector: %{},
        policyTypes: ["Egress"],
        egress: [
          %{
            to: [
              %{
                namespaceSelector: %{
                  matchLabels: %{"kubernetes.io/metadata.name" => "kube-system"}
                }
              }
            ],
            ports: [
              %{protocol: "UDP", port: 53},
              %{protocol: "TCP", port: 53}
            ]
          }
        ]
      }
    }
  end

  defp container(component) do
    %{
      name: Atom.to_string(component.name),
      image: component.image,
      imagePullPolicy: "IfNotPresent",
      ports: [
        %{name: "http", containerPort: component.service_port, protocol: "TCP"}
      ],
      env: Enum.map(component.environment, fn {name, value} -> %{name: name, value: value} end),
      envFrom:
        Enum.map(component.secret_refs, fn name ->
          %{secretRef: %{name: name, optional: false}}
        end),
      resources: %{
        requests: %{
          cpu: "#{component.cpu_request_millis}m",
          memory: "#{component.memory_request_mib}Mi"
        },
        limits: %{
          cpu: "#{component.cpu_limit_millis}m",
          memory: "#{component.memory_limit_mib}Mi"
        }
      },
      livenessProbe: probe(component.health_path, component.service_port),
      readinessProbe: probe(component.readiness_path, component.service_port),
      securityContext: %{
        allowPrivilegeEscalation: false,
        readOnlyRootFilesystem: true,
        runAsNonRoot: true,
        capabilities: %{drop: ["ALL"]}
      }
    }
  end

  defp probe(path, port) do
    %{
      httpGet: %{path: path, port: port, scheme: "HTTP"},
      initialDelaySeconds: 5,
      periodSeconds: 10,
      timeoutSeconds: 2,
      failureThreshold: 3
    }
  end

  defp topology_spread(cell, component) do
    [
      %{
        maxSkew: 1,
        topologyKey: "topology.kubernetes.io/zone",
        whenUnsatisfiable: "DoNotSchedule",
        labelSelector: %{matchLabels: selector_labels(cell, component)}
      },
      %{
        maxSkew: 1,
        topologyKey: "kubernetes.io/hostname",
        whenUnsatisfiable: "ScheduleAnyway",
        labelSelector: %{matchLabels: selector_labels(cell, component)}
      }
    ]
  end

  defp deployment_strategy(:blue_green),
    do: %{type: "RollingUpdate", rollingUpdate: %{maxUnavailable: 0, maxSurge: "100%"}}

  defp deployment_strategy(_other),
    do: %{type: "RollingUpdate", rollingUpdate: %{maxUnavailable: 0, maxSurge: "25%"}}

  defp selector_labels(cell, component) do
    %{
      "app.kubernetes.io/name" => "ash-r2rml",
      "ash-r2rml.io/cell" => cell.id,
      "ash-r2rml.io/role" => Atom.to_string(component.role)
    }
  end

  defp component_labels(plan, cell, component) do
    selector_labels(cell, component)
    |> Map.merge(base_labels(plan))
    |> Map.put("app.kubernetes.io/component", Atom.to_string(component.name))
  end

  defp base_labels(plan) do
    %{
      "app.kubernetes.io/name" => "ash-r2rml",
      "app.kubernetes.io/managed-by" => "ggen",
      "ash-r2rml.io/candidate-sha256" => plan.candidate_id,
      "ash-r2rml.io/authority" => "construct-only"
    }
  end

  defp kube_name(cell, component) do
    "ash-r2rml-#{component.name}-#{cell.id}"
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.trim("-")
    |> String.slice(0, 63)
    |> String.trim_trailing("-")
  end

  defp canary_phases(cells) do
    [
      %{name: "shadow", cells: Enum.take(cells, 1), traffic_percent: 0},
      %{name: "canary-1", cells: Enum.take(cells, 1), traffic_percent: 1},
      %{
        name: "canary-5",
        cells: Enum.take(cells, max(1, div(length(cells), 4))),
        traffic_percent: 5
      },
      %{
        name: "canary-25",
        cells: Enum.take(cells, max(1, div(length(cells), 2))),
        traffic_percent: 25
      },
      %{name: "global", cells: cells, traffic_percent: 100, authority_required?: true}
    ]
  end

  defp cell_progressive_phases(cells) do
    cells
    |> Enum.with_index(1)
    |> Enum.map(fn {cell, index} ->
      %{
        name: "cell-#{index}",
        cells: [cell],
        cumulative_cells: Enum.take(cells, index),
        authority_required?: index == length(cells)
      }
    end)
  end

  defp secret_key?(key) do
    normalized = key |> to_string() |> String.upcase()

    Enum.any?(
      ["PASSWORD", "SECRET", "TOKEN", "API_KEY", "PRIVATE_KEY", "DATABASE_URL"],
      &String.contains?(normalized, &1)
    )
  end

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
    |> Enum.sort()
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(other), do: other
end
