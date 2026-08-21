# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.ControlPlaneTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Fortune5.{DfCM, Quota, Router, SLO, Workload}
  alias AshR2RML.Fortune5.Quota.{Limit, Usage}

  @subject String.duplicate("a", 64)
  @tenant String.duplicate("b", 64)
  @idempotency String.duplicate("c", 64)

  test "SLO calculus produces bounded error budget and burn classification" do
    month = 30 * 24 * 60 * 60 * 1_000
    budget = SLO.downtime_budget_ms(99.99, month)

    assert budget in 259_000..260_000
    assert SLO.classify_burn(SLO.burn_rate(budget / 2, month, 99.99)) == :within_budget
    assert SLO.classify_burn(15.0) == :page
  end

  test "capacity calculus uses Little's Law and refuses invalid input" do
    capacity =
      SLO.capacity(%{
        arrival_rate_per_second: 100_000,
        service_time_ms: 200,
        peak_multiplier: 2.0
      })

    assert capacity.refusals == []
    assert capacity.required_concurrency > 40_000
    assert capacity.required_workers > 0
    assert capacity.required_partitions > 0
    assert capacity.assumptions.calculus == :littles_law
    assert String.length(capacity.receipt_sha256) == 64

    refused = SLO.capacity(%{arrival_rate_per_second: -1, service_time_ms: 0})
    assert refused.refusals != []
  end

  test "SLO evaluation keeps missing observations UNKNOWN" do
    evaluation = SLO.evaluate(%{availability: 100.0, p99_latency: 400})

    assert evaluation.status == :PARTIAL_ALIVE
    assert :availability in evaluation.passed
    assert :p99_latency in evaluation.passed
    assert :receipt_coverage in evaluation.unknown
  end

  test "mutable workload requires semantic identity and idempotency" do
    assert {:error, invalid} =
             Workload.new(%{work_class: :receipted_write, semantic_subject_sha256: @subject})

    assert invalid.code == :REFUSED_MUTATION_WITHOUT_IDEMPOTENCY

    assert {:ok, intent} =
             Workload.new(%{
               work_class: :receipted_write,
               semantic_subject_sha256: @subject,
               tenant_sha256: @tenant,
               idempotency_key_sha256: @idempotency
             })

    assert intent.work_class == :receipted_write
    assert Workload.class(intent).mutable?
  end

  test "unknown work classes fail closed" do
    assert {:error, refusal} =
             Workload.new(%{work_class: :ambient_shell, semantic_subject_sha256: @subject})

    assert refusal.code == :REFUSED_UNKNOWN_WORK_CLASS
  end

  test "quota admission composes global and tenant bounds" do
    limits = [
      %Limit{scope: :global, metric: :concurrent_operations, limit: 100, burst: 10},
      %Limit{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, limit: 10, burst: 2}
    ]

    usages = [
      %Usage{scope: :global, metric: :concurrent_operations, used: 90},
      %Usage{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, used: 8}
    ]

    admitted =
      Quota.admit(
        [
          %{scope: :global, metric: :concurrent_operations, delta: 5},
          %{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, delta: 2}
        ],
        usages,
        limits
      )

    assert admitted.status == :PARTIAL_ALIVE
    assert admitted.refusal_count == 0

    refused =
      Quota.admit(
        [%{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, delta: 5}],
        usages,
        limits
      )

    assert refused.status == :REFUSED
    assert hd(refused.results).code == :REFUSED_QUOTA_EXCEEDED
  end

  test "read routing is deterministic for the same admitted subject and cells" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))
    cells = Router.cells(["us-west-2", "us-east-1"], 3)

    assert {:ok, intent} =
             Workload.new(%{
               work_class: :interactive_read,
               semantic_subject_sha256: @subject,
               tenant_sha256: @tenant
             })

    assert {:ok, first} = Router.route(intent, [candidate], cells)
    assert {:ok, second} = Router.route(intent, [candidate], Enum.reverse(cells))

    assert first.cell_id == second.cell_id
    assert first.route_key_sha256 == second.route_key_sha256
    assert first.plan_sha256 == second.plan_sha256
    assert first.required_authority == :none
  end

  test "region-pinned routing refuses a catalog without the requested region" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))

    assert {:ok, intent} =
             Workload.new(%{
               work_class: :interactive_read,
               semantic_subject_sha256: @subject,
               tenant_sha256: @tenant,
               region: "eu-west-1"
             })

    assert {:error, plan} = Router.route(intent, [candidate], Router.cells(["us-west-2"], 2))
    assert plan.status == :REFUSED
    assert hd(plan.refusals).code == :REFUSED_NO_ELIGIBLE_CELL
  end

  test "write routing requires a receipted-write candidate and a BRCE-capable cell" do
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

    assert {:ok, intent} =
             Workload.new(%{
               work_class: :receipted_write,
               semantic_subject_sha256: @subject,
               tenant_sha256: @tenant,
               idempotency_key_sha256: @idempotency
             })

    [base | _] = Router.cells(["us-west-2"], 1)
    cell = %{base | capabilities: [:sparql_read, :semantic_compile, :ggen_construct, :brce_do]}

    assert {:ok, plan} = Router.route(intent, [candidate], [cell])
    assert plan.required_authority == :brce
    assert plan.standing == :route_constructed_not_executed
  end

  test "quota refusal blocks routing before execution" do
    graph = DfCM.default_graph()
    candidate = DfCM.evaluate(graph, DfCM.default_assignment(graph))

    assert {:ok, intent} =
             Workload.new(%{
               work_class: :interactive_read,
               semantic_subject_sha256: @subject,
               tenant_sha256: @tenant
             })

    quota = %{
      limits: [%Limit{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, limit: 1}],
      usages: [%Usage{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, used: 1}],
      requests: [%{scope: :tenant, scope_sha256: @tenant, metric: :concurrent_operations, delta: 1}]
    }

    assert {:error, plan} = Router.route(intent, [candidate], Router.cells(), quota: quota)
    assert hd(plan.refusals).code == :REFUSED_QUOTA
  end
end
