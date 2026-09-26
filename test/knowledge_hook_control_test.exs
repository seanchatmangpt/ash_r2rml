# SPDX-License-Identifier: MIT
defmodule AshR2RML.KnowledgeHook.ControlTest do
  use ExUnit.Case, async: true
  alias AshR2RML.KnowledgeHook.{Control, Spec, Trigger, Observation, Construct, ReceiptPolicy}

  defp spec(id) do
    %Spec{id: id, name: id, trigger: %Trigger{type: :event},
      observation: %Observation{kind: :external_trigger},
      predicate: %AshR2RML.KnowledgeHook.Predicate{type: :external_trigger},
      construct: %Construct{kind: :workflow, target: "x"}, receipt_policy: %ReceiptPolicy{},
      spec_sha256: "sha256:" <> String.duplicate("a", 64)}
  end

  defp order(extra \\ %{}) do
    Map.merge(%{subject_sha256: "sha256:" <> String.duplicate("1", 64), epoch: 0,
      role: :constructor, policy: :construct_only, authority: [:OBSERVE, :SELECT, :CONSTRUCT],
      max_steps: 8, planners: [:hddl, :fond],
      providers: [%{id: "b", alive?: true, planners: [:hddl]}, %{id: "a", alive?: true, planners: [:hddl]}]}, extra)
  end

  test "selection is deterministic and authority inert" do
    assert {:ok, a} = Control.admit([spec("x")], order())
    assert {:ok, b} = Control.admit([spec("x")], order())
    assert a == b
    assert a.planner == :hddl and a.provider == "a"
    assert a.authority == :UNAUTHORIZED
  end

  test "refuses authority laundering and unbounded construction" do
    assert {:error, _} = Control.admit([spec("x")], order(%{authority: [:DO]}))
    assert {:error, _} = Control.admit([spec("x")], order(%{max_steps: 0}))
  end

  test "duplicate enqueue is replay, capacity is fail closed" do
    {:ok, wo} = Control.admit([spec("x")], order())
    s = Control.new(capacity: 1)
    assert {:ok, s, _} = Control.enqueue(s, wo)
    assert {:ok, ^s, %{status: :KNOWN_REPLAY}} = Control.enqueue(s, wo)
  end

  test "provider extinction reclaims lease and rotates epoch" do
    {:ok, wo} = Control.admit([spec("x")], order())
    s = Control.new(providers: [%{id: "a", planners: [:hddl]}])
    {:ok, s, _} = Control.enqueue(s, wo)
    {:ok, s, lease, _} = Control.lease(s, "a", 10)
    s = Control.extinct(s, "a")
    assert s.epoch == 1
    assert map_size(s.leases) == 0
    assert :queue.len(s.queue) == 1
    assert {:error, :unknown_or_stale_lease, _} = Control.complete(s, lease.id, %{steps: 1})
  end

  test "completion refuses consequence and bound escape" do
    {:ok, wo} = Control.admit([spec("x")], order())
    s = Control.new(providers: [%{id: "a", planners: [:hddl]}])
    {:ok, s, _} = Control.enqueue(s, wo)
    {:ok, s, lease, _} = Control.lease(s, "a", 10)
    assert {:error, :authority_laundering, _} = Control.complete(s, lease.id, %{steps: 1, consequence: :write})
    assert {:error, :construction_bound_exceeded, _} = Control.complete(s, lease.id, %{steps: 99})
  end
end
