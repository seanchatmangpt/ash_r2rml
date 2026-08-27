# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.IdempotencyTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Idempotency

  test "admits receipted replay" do
    assert {:ok, %{replay_behavior: :return_prior_receipt}} =
             Idempotency.admit(%{key: "request-1", receipt_namespace: "project2/runtime"})
  end

  test "refuses an unreceipted idempotency key" do
    assert {:error, :REFUSED_RUNTIME_IDEMPOTENCY_INCOMPLETE} = Idempotency.admit(%{key: "request-1"})
  end
end
