# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.AuditTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Audit

  @digest String.duplicate("a", 64)

  test "admits append-only receipted audit" do
    assert {:ok, %{append_only: true}} =
             Audit.admit(%{actor_id: "actor-1", subject_digest: @digest, action: "construct", receipt_id: "r1"})
  end

  test "refuses non-exact subject digest" do
    assert {:error, :REFUSED_RUNTIME_AUDIT_INCOMPLETE} =
             Audit.admit(%{actor_id: "actor-1", subject_digest: "short", action: "construct", receipt_id: "r1"})
  end
end
