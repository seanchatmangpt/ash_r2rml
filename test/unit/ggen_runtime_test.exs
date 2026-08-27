# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntimeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime

  test "manufactures a deterministic construct-only runtime contract" do
    input = %{
      subject: %{repo: "seanchatmangpt/ash_r2rml", base: "main", head: "067954ad406fd637"},
      authority: %{policy: "project2", action: "construct"},
      runtime: %{resource: "Example.Resource", action: "read"}
    }

    assert {:ok, first} = GgenRuntime.contract(input)
    assert {:ok, second} = GgenRuntime.contract(input)
    assert first == second
    assert first.status == :PARTIAL_ALIVE
    assert first.standing == :construct_only
    assert first.marketplace_pack == "ash-runtime-integration-contract-pack"
    assert byte_size(first.runtime_digest) == 64
    assert byte_size(first.replay_key) == 64
  end

  test "canonical Ggen API delegates runtime contract manufacture" do
    input = %{
      subject: %{repo: "seanchatmangpt/ash_r2rml", base: "main", head: "067954ad406fd637"},
      authority: %{policy: "project2", action: "construct"},
      runtime: %{resource: "Example.Resource", action: "read"}
    }

    assert AshR2RML.Ggen.compile_runtime_contract(input) == GgenRuntime.contract(input)
  end

  test "preserves an explicit replay identity" do
    assert {:ok, contract} =
             GgenRuntime.contract(%{
               subject: %{repo: "seanchatmangpt/ash_r2rml", base: "main", head: "067954ad"},
               authority: %{policy: "project2", action: "construct"},
               runtime: %{resource: "Example.Resource", action: "read"},
               replay_key: "receipt-42"
             })

    assert contract.replay_key == "receipt-42"
  end

  test "refuses a non-exact subject" do
    assert {:error, :REFUSED_RUNTIME_SUBJECT_NOT_EXACT} =
             GgenRuntime.contract(%{
               subject: %{repo: "x/y", base: "main", head: "bad"},
               authority: %{policy: "project2", action: "construct"},
               runtime: %{}
             })
  end

  test "refuses missing authority" do
    assert {:error, :REFUSED_RUNTIME_AUTHORITY_MISSING} =
             GgenRuntime.contract(%{
               subject: %{repo: "seanchatmangpt/ash_r2rml", base: "main", head: "067954ad"},
               authority: %{},
               runtime: %{}
             })
  end
end
