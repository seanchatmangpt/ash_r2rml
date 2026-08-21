# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Production.Deployment do
  @moduledoc """
  Platform-neutral deployment composition and Kubernetes projection.

  A deployment plan is CONSTRUCT-only. It contains no cloud credentials and
  never applies generated objects.
  """

  alias AshR2RML.DfCM.Candidate
  alias AshR2RML.Production.{Observability, Release, Resilience, Security}

  defmodule Role do
    @moduledoc "One runtime/process role with an explicit authority envelope."
    defstruct [:id, :replicas, :authority, :network, :resources, :health, env: %{}]
    @type t :: %__MODULE__{}
  end

  defmodule Cell do
    @moduledoc "One regional failure-isolation cell."
    defstruct [:id, :region, :zone_count, :weight, :status]
    @type t :: %__MODULE__{}
  end

  defmodule Plan do
    @moduledoc "Deployment model derived from one DfCM candidate."
    defstruct [
      :candidate_id,
      :assignment,
      :semantic_subject_sha256,
      :security,
      :observability,
      :resilience,
      :release,
      roles: [],
      cells: [],
      invariants: []
    ]

    @type t :: %__MODULE__{}
  end

  @spec plan(Candidate.t(), String.t(), keyword()) :: Plan.t()
  def plan(%Candidate{} = candidate, semantic_subject_sha256, opts \\ []) do
    regions = Keyword.get(opts, :regions, ["us-west-2", "us-east-1"])
    cells_per_region = Keyword.get(opts, :cells_per_region, 3)
    zones_per_region = Keyword.get(opts, :zones_per_region, 3)
    assignment = candidate.assignment

    %Plan{
      candidate_id: candidate.id,
      assignment: assignment,
      semantic_subject_sha256: semantic_subject_sha256,
      roles: roles(assignment),
      cells: cells(assignment, regions, cells_per_region, zones_per_region),
      security: Security.contract(assignment),
      observability: Observability.contract(assignment, semantic_subject_sha256),
      resilience: Resilience.contract(assignment, %{max_recovery_point_seconds: 60, max_recovery_time_seconds: 300}),
      release: Release.contract(assignment),
      invariants: [
        :no_secret_material_in_plan,
        :brce_is_only_do_role,
        :generated_objects_are_construct_only,
        :semantic_subject_bound_to_every_role,
        :default_deny_network,
        :non_root_runtime
      ]
    }
  end

  @spec kubernetes(Plan.t(), keyword()) :: [map()]
  def kubernetes(%Plan{} = plan, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, "ash-r2rml")
    image = Keyword.get(opts, :image, "ash-r2rml@sha256:REQUIRED")

    role_objects =
      Enum.flat_map(plan.roles, fn role ->
        [
          service_account(namespace, role),
          deployment(namespace, image, plan, role),
          service(namespace, role),
          network_policy(namespace, role),
          pdb(namespace, role),
          hpa(namespace, role)
        ]
      end)

    [namespace_object(namespace), config_map(namespace, plan) | role_objects]
  end

  @spec validate(Plan.t()) :: :ok | {:error, [map()]}
  def validate(%Plan{} = plan) do
    do_roles = Enum.filter(plan.roles, &(&1.authority == :do))

    refusals =
      []
      |> maybe_refuse(Enum.any?(plan.roles, &contains_secret?/1), :REFUSED_SECRET_IN_DEPLOYMENT_PLAN)
      |> maybe_refuse(Enum.any?(do_roles, &(&1.id != :brce_actuator)), :REFUSED_NON_BRCE_DO_ROLE)
      |> maybe_refuse(length(do_roles) > 1, :REFUSED_MULTIPLE_DO_AUTHORITIES)

    if refusals == [], do: :ok, else: {:error, Enum.reverse(refusals)}
  end

  defp roles(assignment) do
    execution_mode = Map.get(assignment, :execution_mode, :compile_only)

    base = [
      role(:compiler, 2, :construct, [:semantic_input], %{cpu: "500m", memory: "512Mi"}),
      role(:ggen_manufacturer, 2, :construct, [:semantic_input, :generated_output], %{cpu: "1", memory: "1Gi"}),
      role(:verifier, 2, :observe, [:generated_output, :runtime_observation], %{cpu: "500m", memory: "512Mi"})
    ]

    runtime =
      if execution_mode == :compile_only do
        []
      else
        [role(:semantic_runtime, 3, :runtime, [:database, :obda, :telemetry], %{cpu: "1", memory: "1Gi"})]
      end

    actuator =
      if execution_mode == :receipted_write_runtime do
        [role(:brce_actuator, 2, :do, [:database, :authority_service, :receipt_store], %{cpu: "1", memory: "1Gi"})]
      else
        []
      end

    base ++ runtime ++ actuator
  end

  defp role(id, replicas, authority, network, resources) do
    %Role{
      id: id,
      replicas: replicas,
      authority: authority,
      network: network,
      resources: resources,
      health: %{liveness: "/health/live", readiness: "/health/ready"},
      env: %{}
    }
  end

  defp cells(assignment, regions, cells_per_region, zones_per_region) do
    topology = Map.get(assignment, :deployment_topology, :active_passive)
    count = if topology == :cellular, do: cells_per_region, else: 1

    for region <- Enum.sort(regions), ordinal <- 1..count do
      %Cell{id: "#{region}-c#{ordinal}", region: region, zone_count: zones_per_region, weight: 1, status: :planned}
    end
  end

  defp namespace_object(namespace) do
    %{apiVersion: "v1", kind: "Namespace", metadata: %{name: namespace, labels: %{"app.kubernetes.io/part-of" => "ash-r2rml"}}}
  end

  defp service_account(namespace, role) do
    %{
      apiVersion: "v1",
      kind: "ServiceAccount",
      metadata: %{name: role_name(role), namespace: namespace},
      automountServiceAccountToken: false
    }
  end

  defp deployment(namespace, image, plan, role) do
    labels = labels(role)

    %{
      apiVersion: "apps/v1",
      kind: "Deployment",
      metadata: %{name: role_name(role), namespace: namespace, labels: labels},
      spec: %{
        replicas: role.replicas,
        selector: %{matchLabels: labels},
        template: %{
          metadata: %{labels: labels},
          spec: %{
            serviceAccountName: role_name(role),
            automountServiceAccountToken: false,
            securityContext: %{runAsNonRoot: true, seccompProfile: %{type: "RuntimeDefault"}},
            containers: [
              %{
                name: Atom.to_string(role.id),
                image: image,
                imagePullPolicy: "IfNotPresent",
                args: ["--role", Atom.to_string(role.id)],
                env: [
                  %{name: "ASH_R2RML_SEMANTIC_SUBJECT_SHA256", value: plan.semantic_subject_sha256},
                  %{name: "ASH_R2RML_AUTHORITY_CLASS", value: Atom.to_string(role.authority)}
                ],
                resources: %{requests: role.resources, limits: role.resources},
                securityContext: %{
                  allowPrivilegeEscalation: false,
                  readOnlyRootFilesystem: true,
                  runAsNonRoot: true,
                  capabilities: %{drop: ["ALL"]}
                },
                readinessProbe: %{httpGet: %{path: role.health.readiness, port: 4000}},
                livenessProbe: %{httpGet: %{path: role.health.liveness, port: 4000}}
              }
            ]
          }
        }
      }
    }
  end

  defp service(namespace, role) do
    %{apiVersion: "v1", kind: "Service", metadata: %{name: role_name(role), namespace: namespace}, spec: %{selector: labels(role), ports: [%{port: 4000, targetPort: 4000}]}}
  end

  defp network_policy(namespace, role) do
    %{
      apiVersion: "networking.k8s.io/v1",
      kind: "NetworkPolicy",
      metadata: %{name: "#{role_name(role)}-default-deny", namespace: namespace},
      spec: %{podSelector: %{matchLabels: labels(role)}, policyTypes: ["Ingress", "Egress"]}
    }
  end

  defp pdb(namespace, role) do
    %{apiVersion: "policy/v1", kind: "PodDisruptionBudget", metadata: %{name: role_name(role), namespace: namespace}, spec: %{minAvailable: 1, selector: %{matchLabels: labels(role)}}}
  end

  defp hpa(namespace, role) do
    %{
      apiVersion: "autoscaling/v2",
      kind: "HorizontalPodAutoscaler",
      metadata: %{name: role_name(role), namespace: namespace},
      spec: %{
        scaleTargetRef: %{apiVersion: "apps/v1", kind: "Deployment", name: role_name(role)},
        minReplicas: role.replicas,
        maxReplicas: max(role.replicas * 10, 10),
        metrics: [%{type: "Resource", resource: %{name: "cpu", target: %{type: "Utilization", averageUtilization: 65}}}]
      }
    }
  end

  defp config_map(namespace, plan) do
    %{
      apiVersion: "v1",
      kind: "ConfigMap",
      metadata: %{name: "ash-r2rml-production", namespace: namespace},
      data: %{
        "candidate_sha256" => plan.candidate_id,
        "semantic_subject_sha256" => plan.semantic_subject_sha256,
        "standing" => "construct_only"
      }
    }
  end

  defp labels(role), do: %{"app.kubernetes.io/name" => "ash-r2rml", "ash-r2rml/role" => Atom.to_string(role.id)}
  defp role_name(role), do: "ash-r2rml-#{String.replace(Atom.to_string(role.id), "_", "-")}"

  defp contains_secret?(role) do
    role.env
    |> Enum.any?(fn {key, _value} -> String.contains?(String.downcase(to_string(key)), ["secret", "password", "token", "key"]) end)
  end

  defp maybe_refuse(acc, true, code), do: [%{code: code} | acc]
  defp maybe_refuse(acc, false, _code), do: acc
end
