# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.ReplayTest do
  use ExUnit.Case, async: true
  alias AshR2RML.GgenRuntime.Replay

  @digest String.duplicate("b", 64)

  test "admits exact deterministic replay" do
    assert {:ok, %{mode: :deterministic}} = Replay.admit(%{contract_digest: @digest, receipt_id: "receipt-1"})
  end

  test "refuses replay without receipt" do
    assert {:error, :REFUSED_RUNTIME_REPLAY_IDENTITY_INCOMPLETE} = Replay.admit(%{contract_digest: @digest})
  end
end
