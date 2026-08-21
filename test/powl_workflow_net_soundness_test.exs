# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.POWL.WorkflowNetSoundnessTest do
  use ExUnit.Case, async: true

  alias AshR2RML.POWL.WorkflowNet

  test "simple workflow receives an explicit bounded ALIVE receipt" do
    net = WorkflowNet.new(:source, :sink, [:middle], [:a, :b], %{}, [
      {:source, :a}, {:a, :middle}, {:middle, :b}, {:b, :sink}
    ])

    assert :ok = WorkflowNet.verify_structure(net)
    assert {:ok, report} = WorkflowNet.soundness_report(net)
    assert report.status == :ALIVE
    assert report.final_marking == %{sink: 1}
    assert report.place_bound == 1
    assert report.proof_scope == :exhaustive_within_admitted_bounds
  end

  test "non-bipartite flow is refused structurally" do
    net = WorkflowNet.new(:source, :sink, [:p], [:a], %{}, [
      {:source, :p}, {:p, :a}, {:a, :sink}
    ])

    assert {:error, refusal} = WorkflowNet.verify_structure(net)
    assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
    assert refusal.evidence.invalid_arcs == [{:source, :p}]
  end

  test "token multiplicity falsifies the old MapSet 1-safety proof" do
    net = WorkflowNet.new(:source, :sink, [:left, :right], [:split, :left_done, :right_done], %{}, [
      {:source, :split}, {:split, :left}, {:split, :right},
      {:left, :left_done}, {:right, :right_done},
      {:left_done, :sink}, {:right_done, :sink}
    ])

    assert {:error, refusal} = WorkflowNet.soundness_report(net)
    assert refusal.code == :REFUSED_UNSAFE_WORKFLOW_NET
    assert refusal.evidence.place_bound == 1
    assert refusal.evidence.marking[:sink] == 2
  end

  test "proper completion rejects a sink token with residual work" do
    net = WorkflowNet.new(
      :source,
      :sink,
      [:good, :left, :right],
      [:choose_good, :finish_good, :choose_bad, :left_done, :right_done],
      %{},
      [
        {:source, :choose_good}, {:choose_good, :good}, {:good, :finish_good}, {:finish_good, :sink},
        {:source, :choose_bad}, {:choose_bad, :left}, {:choose_bad, :right},
        {:left, :left_done}, {:right, :right_done},
        {:left_done, :sink}, {:right_done, :sink}
      ]
    )

    assert {:error, refusal} = WorkflowNet.soundness_report(net, place_bound: 2)
    assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
    assert refusal.detail =~ "proper completion"
    assert Map.get(refusal.evidence.witness, :sink, 0) > 0
    assert map_size(refusal.evidence.witness) > 1
  end

  test "exhausting the admitted exploration budget stays UNKNOWN" do
    net = WorkflowNet.new(:source, :sink, [:middle], [:a, :b], %{}, [
      {:source, :a}, {:a, :middle}, {:middle, :b}, {:b, :sink}
    ])

    assert {:unknown, report} = WorkflowNet.soundness_report(net, max_states: 1)
    assert report.status == :UNKNOWN
    assert report.reason == :state_space_bound_exceeded
  end

  test "graph connectivity alone does not hide an unreachable synchronization" do
    net = WorkflowNet.new(:source, :sink, [:left, :right], [:choose_left, :choose_right, :join], %{}, [
      {:source, :choose_left}, {:source, :choose_right},
      {:choose_left, :left}, {:choose_right, :right},
      {:left, :join}, {:right, :join}, {:join, :sink}
    ])

    assert :ok = WorkflowNet.verify_structure(net)
    assert {:error, refusal} = WorkflowNet.soundness_report(net)
    assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
  end
end
