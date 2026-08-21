# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ProductionControlPlaneTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Production.{Quota, Router, SLO, Workload}

  test "capacity is derived from Little's Law with explicit headroom" do
    capacity =
      SLO.capacity(%{arrival_rate_per_second: 10_000, service_time_ms: 100},
        headroom: 1.5,
        max_inflight_per_replica: 1_000
      )

    assert capacity.target_concurrency == 1_500
    assert capacity.minimum_replicas == 2
    assert capacity.little_law_identity == :lambda_times_w
  end

  test "DO workload requires idempotency before routing" do
    attrs = %{
      id: "w-1",
      tenant_id: "tenant-a",
      semantic_subject_sha256: String.duplicate("a", 64),
      mode: :do,
      residency: :regional
    }

    assert {:error, %{code: :REFUSED_DO_WITHOUT_IDEMPOTENCY_KEY}} = Workload.new(attrs)

    assert {:ok, workload} = Workload.new(Map.put(attrs, :idempotency_key, "idem-1"))
    assert workload.mode == :do
  end

  test "hierarchical quota fails closed on unknown usage" do
    quotas = [
      %Quota{id: :global, scope: :global, max_inflight: 100, max_rps: 100, current_inflight: nil, current_rps: 1}
    ]

    assert {:error, %{code: :REFUSED_QUOTA_STATE_UNKNOWN}} = Quota.admit(quotas)
  end

  test "hierarchical quota refuses overflow" do
    quotas = [
      %Quota{id: :tenant, scope: :tenant, max_inflight: 10, max_rps: 10, current_inflight: 10, current_rps: 1}
    ]

    assert {:error, %{code: :REFUSED_QUOTA_EXCEEDED}} = Quota.admit(quotas)
  end

  test "regional routing is deterministic and receipt-addressed" do
    {:ok, workload} =
      Workload.new(%{
        id: "read-1",
        tenant_id: "tenant-a",
        semantic_subject_sha256: String.duplicate("b", 64),
        mode: :read,
        residency: :regional,
        required_capabilities: [:obda]
      })

    cells = Router.cells(["us-west-2", "us-east-1"], 3)

    assert {:ok, first} = Router.route(workload, cells, region: "us-west-2")
    assert {:ok, second} = Router.route(workload, cells, region: "us-west-2")
    assert first == second
    assert first.region == "us-west-2"
    assert first.do_authority == :none
  end

  test "country-bound routing refuses when no matching cell exists" do
    {:ok, workload} =
      Workload.new(%{
        id: "read-2",
        tenant_id: "tenant-a",
        semantic_subject_sha256: String.duplicate("c", 64),
        mode: :read,
        residency: :country_bound
      })

    assert {:error, %{code: :REFUSED_NO_ELIGIBLE_CELL}} =
             Router.route(workload, Router.cells(["us-west-2"]), country: "CA")
  end
end
