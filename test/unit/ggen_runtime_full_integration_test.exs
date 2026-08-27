# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.FullIntegrationTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.FullIntegration

  @sha String.duplicate("a", 40)
  @digest String.duplicate("b", 64)

  defp input do
    %{
      subject: %{repo: "seanchatmangpt/ash_r2rml", base: @sha, head: @sha},
      authority: %{policy: "project2", action: :construct},
      observability: %{correlation_id: "c1", trace_id: "t1", evidence: "ggen/ecosystem/ocel/current"},
      resilience: %{timeout_ms: 5_000, max_attempts: 3},
      concurrency: %{strategy: :optimistic, version_field: :version, conflict: :refuse},
      transport: %{kind: :api, max_page_size: 100, max_batch_size: 500},
      security: %{actor: %{id: "actor-1"}, policy: "ash-field-policy"},
      data_contract: %{input_schema: %{id: :uuid}, output_schema: %{name: :string}},
      eventing: %{event_id: "e1", correlation_id: "c1", receipt_id: "r1"},
      persistence: %{backend: :ash_postgres, transaction: :ash},
      idempotency: %{key: "request-1", receipt_namespace: "project2/runtime"},
      reactor: %{step: "construct", on_error: :refuse},
      fault_isolation: %{failure_threshold: 5, max_concurrency: 100},
      cache: %{mode: :none, consistency: :strong},
      lifecycle: %{state: :active},
      rate_limit: %{limit: 100, window_ms: 60_000, partition_by: :actor},
      audit: %{actor_id: "actor-1", subject_digest: @digest, action: "construct", receipt_id: "r1"},
      replay: %{contract_digest: @digest, receipt_id: "r1"},
      config: %{dependencies: %{ash: "3.32.0"}, runtime: %{elixir: "1.18.4"}},
      deadline: %{deadline_ms: 5_000, cancellation: :cooperative},
      isolation: %{tenant: :context, transaction: :serializable}
    }
  end

  test "admits full contract" do
    assert {:ok, contract} = FullIntegration.admit(input())
    assert contract.contract_level == :full
    assert contract.marketplace_pack == "ash-runtime-integration-contract-pack"
    assert contract.audit.append_only
    assert contract.idempotency.replay_behavior == :return_prior_receipt
  end

  test "one optional operational seam can refuse the full contract" do
    invalid = put_in(input(), [:rate_limit, :partition_by], :global)
    assert {:error, :REFUSED_RUNTIME_RATE_LIMIT_INCOMPLETE} = FullIntegration.admit(invalid)
  end
end
