# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ProductionDeploymentTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DfCM
  alias AshR2RML.Production
  alias AshR2RML.Production.Deployment

  @subject String.duplicate("d", 64)

  test "deployment model is platform-neutral and contains no ambient DO" do
    assert {:ok, [candidate], _receipt} =
             DfCM.enumerate(Production.design_space(), select: Production.default_assignment())

    plan = Deployment.plan(candidate, @subject)

    assert :ok = Deployment.validate(plan)
    refute Enum.any?(plan.roles, &(&1.authority == :do))
    assert plan.security.ambient_authority == false
    assert :vendor_specific_projection_owned_by_ggen in plan.invariants
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

  test "cellular topology expands failure-isolation cells without changing semantic identity" do
    assignment =
      Production.default_assignment()
      |> Map.put(:deployment_topology, :cellular)
      |> Map.put(:control_plane, :cellular)

    assert {:ok, candidate} = DfCM.admit(Production.design_space(), assignment)

    plan =
      Deployment.plan(candidate, @subject,
        regions: ["us-west-2", "us-east-1"],
        cells_per_region: 3,
        zones_per_region: 3
      )

    assert length(plan.cells) == 6
    assert Enum.all?(plan.cells, &(&1.zone_count == 3))
    assert plan.semantic_subject_sha256 == @subject
  end

  test "vendor-specific Kubernetes manufacture lives in ggen workspace" do
    manifest = File.read!("production/ggen/ggen.toml")
    template = File.read!("production/ggen/templates/kubernetes-candidate.yaml.tmpl")

    assert manifest =~ ~s(name = "kubernetes-candidate")
    assert manifest =~ ~s(template = { file = "templates/kubernetes-candidate.yaml.tmpl" })
    assert template =~ "kind: NetworkPolicy"
    assert template =~ "automountServiceAccountToken: false"
    assert template =~ "readOnlyRootFilesystem: true"
    assert template =~ "capabilities: {drop: [\"ALL\"]}"
    refute template =~ "kind: Secret"
    refute template =~ "{{ now()"
  end
end
