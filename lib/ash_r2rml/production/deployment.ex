# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Production.Deployment do
  @moduledoc """
  Platform-neutral deployment composition for an admitted DfCM candidate.

  The plan describes process roles, authority envelopes, failure-isolation cells,
  resources and operational contracts. It deliberately does not render
  Kubernetes, Terraform, Helm, cloud APIs or another vendor-specific artifact.
  Those are ggen-owned projections under `production/ggen/`.

  A deployment plan is CONSTRUCT-only. It contains no cloud credentials and
  never applies infrastructure.
  """

  alias AshR2RML.DfCM.Candidate
  alias AshR2RML.Production.{Observability, Release, Resilience, Security}

  defmodule Role do
    @moduledoc "One runtime/process role with an explicit authority envelope."
    defstruct [:id, :replicas, :authority, :network, :resources, :health, env: %{}]
    @type t :: %__MODULE__{}
  end

  defmodule Cell do
    @moduledoc "One planned regional failure-isolation cell."
    defstruct [:id, :region, :zone_count, :weight, :status]
    @type t :: %__MODULE__{}
  end

  defmodule Plan do
    @moduledoc "Platform-neutral deployment model derived from one DfCM candidate."
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
      resilience:
        Resilience.contract(assignment, %{
          max_recovery_point_seconds: 60,
          max_recovery_time_seconds: 300
        }),
      release: Release.contract(assignment),
      invariants: [
        :no_secret_material_in_plan,
        :brce_is_only_do_role,
        :vendor_specific_projection_owned_by_ggen,
        :semantic_subject_bound_to_every_role,
        :default_deny_network,
        :non_root_runtime
      ]
    }
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
      %Cell{
        id: "#{region}-c#{ordinal}",
        region: region,
        zone_count: zones_per_region,
        weight: 1,
        status: :planned
      }
    end
  end

  defp contains_secret?(role) do
    Enum.any?(role.env, fn {key, _value} ->
      String.contains?(String.downcase(to_string(key)), ["secret", "password", "token", "key"])
    end)
  end

  defp maybe_refuse(acc, true, code), do: [%{code: code} | acc]
  defp maybe_refuse(acc, false, _code), do: acc
end
