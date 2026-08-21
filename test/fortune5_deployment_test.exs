# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.DeploymentTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.{Deployment, DfCM}

  test "default candidate expands to an admitted multi-region deployment plan" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))

    assert {:ok, plan} = Deployment.plan(candidate)
    assert plan.status == :PARTIAL_ALIVE
    assert plan.standing == :deployment_plan_constructed_not_actuated
    assert length(plan.regions) == 2
    assert length(plan.cells) == 2
    assert String.length(plan.plan_sha256) == 64
    assert :brce_only_do in plan.invariants
    assert :no_plaintext_secrets in plan.invariants
  end

  test "cellular candidate creates multiple cells per region and progressive rollout" do
    graph = DfCM.default_graph()

    assignment =
      graph
      |> DfCM.default_assignment()
      |> Map.merge(%{
        deployment_topology: :cellular_multi_region,
        partition_strategy: :hybrid,
        release_strategy: :cell_progressive,
        control_plane: :cellular_federated,
        consistency_model: :strong,
        disaster_recovery: :active_active
      })

    candidate = DfCM.evaluate(graph, assignment)
    assert candidate.refusals == []

    assert {:ok, plan} = Deployment.plan(candidate, cells_per_region: 3)
    assert length(plan.regions) == 3
    assert length(plan.cells) == 9

    rollout = Deployment.rollout_matrix(plan)
    assert rollout.strategy == :cell_progressive
    assert length(rollout.phases) == 9
    assert List.last(rollout.phases).authority_required?
  end

  test "receipted write deployment isolates DO capability to BRCE actuator" do
    graph = DfCM.default_graph()

    assignment =
      graph
      |> DfCM.default_assignment()
      |> Map.merge(%{
        execution_mode: :receipted_write_runtime,
        observability: :open_telemetry_receipts,
        migration_strategy: :expand_contract
      })

    candidate = DfCM.evaluate(graph, assignment)
    assert {:ok, plan} = Deployment.plan(candidate)

    components = Enum.flat_map(plan.cells, & &1.components)
    actuators = Enum.filter(components, &(:perform_bounded_do in &1.capabilities))

    assert actuators != []
    assert Enum.all?(actuators, &(&1.role == :brce_actuator and &1.authority == :do))
    assert :ok = Deployment.validate(plan)
  end

  test "insufficient region inventory refuses multi-region closure" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))

    assert {:error, plan} = Deployment.plan(candidate, regions: ["only-region"])
    assert plan.status == :REFUSED
    assert Enum.any?(plan.refusals, &(&1.code == :REFUSED_DEPLOYMENT_REGION_CLOSURE))
  end

  test "Kubernetes projection contains no Secret objects and defaults network to deny" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))
    assert {:ok, plan} = Deployment.plan(candidate)

    objects = Deployment.kubernetes(plan)
    kinds = Enum.map(objects, & &1.kind)

    assert "Namespace" in kinds
    assert "Deployment" in kinds
    assert "Service" in kinds
    assert "PodDisruptionBudget" in kinds
    assert "HorizontalPodAutoscaler" in kinds
    assert "NetworkPolicy" in kinds
    refute "Secret" in kinds

    default_deny =
      Enum.find(objects, fn object ->
        object.kind == "NetworkPolicy" and object.metadata.name == "ash-r2rml-default-deny"
      end)

    assert default_deny.spec.policyTypes == ["Ingress", "Egress"]
    assert default_deny.spec.podSelector == %{}
  end

  test "Kubernetes workloads run non-root, read-only, drop capabilities and do not automount service tokens" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))
    assert {:ok, plan} = Deployment.plan(candidate)

    deployments = Enum.filter(Deployment.kubernetes(plan), &(&1.kind == "Deployment"))
    assert deployments != []

    for deployment <- deployments do
      pod = deployment.spec.template.spec
      assert pod.automountServiceAccountToken == false
      assert pod.securityContext.runAsNonRoot == true

      for container <- pod.containers do
        assert container.securityContext.allowPrivilegeEscalation == false
        assert container.securityContext.readOnlyRootFilesystem == true
        assert container.securityContext.runAsNonRoot == true
        assert container.securityContext.capabilities.drop == ["ALL"]
      end
    end
  end

  test "scheduler projection preserves authority and external secret references as references" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))
    assert {:ok, plan} = Deployment.plan(candidate)

    scheduler = Deployment.scheduler(plan)
    assert scheduler.candidate_id == candidate.id
    assert scheduler.workloads != []

    query = Enum.find(scheduler.workloads, &(&1.role == :query_verifier))
    assert query.authority == :read
    assert "postgres-readonly" in query.secret_refs
    refute Map.has_key?(query.environment, "DATABASE_URL")
  end
end
