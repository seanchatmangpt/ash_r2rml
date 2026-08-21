# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ProductionDeploymentTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DfCM
  alias AshR2RML.Production
  alias AshR2RML.Production.Deployment

  @subject String.duplicate("d", 64)

  test "deployment model separates roles and contains no ambient DO" do
    assert {:ok, [candidate], _} =
             DfCM.enumerate(Production.design_space(), select: Production.default_assignment())

    plan = Deployment.plan(candidate, @subject)

    assert :ok = Deployment.validate(plan)
    refute Enum.any?(plan.roles, &(&1.authority == :do))
    assert plan.security.ambient_authority == false
  end

  test "receipted write runtime creates exactly one BRCE DO role" do
    assignment =
      Production.default_assignment()
      |> Map.put(:execution_mode, :receipted_write_runtime)
      |> Map.put(:recovery_strategy, :failover_replay)

    assert {:ok, candidate} = DfCM.admit(Production.design_space(), assignment)
    plan = Deployment.plan(candidate, @subject)

    do_roles = Enum.filter(plan.roles, &(&1.authority == :do))
    assert Enum.map(do_roles, & &1.id) == [:brce_actuator]
    assert :ok = Deployment.validate(plan)
  end

  test "Kubernetes is a projection with default-deny and hardened containers" do
    assert {:ok, [candidate], _} =
             DfCM.enumerate(Production.design_space(), select: Production.default_assignment())

    plan = Deployment.plan(candidate, @subject)
    objects = Deployment.kubernetes(plan, image: "example.invalid/ash-r2rml@sha256:abc")

    refute Enum.any?(objects, &(Map.get(&1, :kind) == "Secret"))
    assert Enum.any?(objects, &(Map.get(&1, :kind) == "NetworkPolicy"))
    assert Enum.any?(objects, &(Map.get(&1, :kind) == "HorizontalPodAutoscaler"))

    deployments = Enum.filter(objects, &(Map.get(&1, :kind) == "Deployment"))

    assert Enum.all?(deployments, fn object ->
             [container] = object.spec.template.spec.containers
             container.securityContext.runAsNonRoot == true and
               container.securityContext.readOnlyRootFilesystem == true and
               container.securityContext.allowPrivilegeEscalation == false and
               container.securityContext.capabilities.drop == ["ALL"]
           end)
  end
end
