# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.IntegrationTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Integration

  @sha String.duplicate("a", 40)

  defp valid_input do
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
      persistence: %{backend: :ash_postgres, transaction: :ash}
    }
  end

  test "admits and deterministically digests the complete runtime contract" do
    assert {:ok, first} = Integration.admit(valid_input())
    assert {:ok, second} = Integration.admit(valid_input())
    assert first == second
    assert first.standing == :construct_only
    assert first.canonical_evidence == "ggen/ecosystem/ocel/current"
    assert byte_size(first.contract_digest) == 64
  end

  test "one failed seam refuses the whole integrated subject" do
    input = put_in(valid_input(), [:persistence, :direct_sql], true)
    assert {:error, :REFUSED_RUNTIME_PERSISTENCE_AUTHORITY_ESCAPE} = Integration.admit(input)
  end
end
