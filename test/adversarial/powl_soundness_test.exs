# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.PowlSoundnessTest do
  @moduledoc """
  Hostile Adversarial Test Suite for Workflow Net (WF-net) Structural Properties
  and Mathematical 1-Safe Soundness Verification (van der Aalst Process Science).

  Exercises:
  1. Structural Precondition Refusals:
     - Multiple sources / Multiple sinks
     - Disjointness violations (overlapping place/transition nodes)
     - Non-bipartite edges (place->place, transition->transition)
     - Orphan transitions (empty preset or postset)
     - Disconnected nodes (no path from source / no path to sink)
  2. Soundness Violations:
     - Dead transitions (unreachable or mutually exclusive join)
     - Classical Deadlocks (AND-join after XOR-split)
     - Improper Completion (XOR-join after AND-split / leftover tokens)
     - Livelocks (inescapable loops unable to reach sink)
     - 1-Safety violations (token accumulation / contact)
     - State space explosion cutoff bounds
  3. Certified Sound Workflow Nets:
     - Sequential nets
     - Concurrent Marked Graphs (AND-split + AND-join)
     - Exclusive State Machines (XOR-split + XOR-join)
     - Sound looping nets
  """
  use ExUnit.Case, async: true

  alias AshR2RML.POWL.WorkflowNet
  alias AshR2RML.Refusal

  describe "1. Structural Precondition Verifications & Typed Refusals" do
    test "refuses WF-net with multiple source places" do
      places = [:p_src1, :p_src2, :p_a, :p_snk]
      transitions = [:t1, :t2]
      labels = %{t1: "T1", t2: "T2"}
      flow = [{:p_src1, :t1}, {:p_src2, :t1}, {:t1, :p_a}, {:p_a, :t2}, {:t2, :p_snk}]

      net = WorkflowNet.new(:p_src1, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "source"
    end

    test "refuses WF-net with multiple sink places" do
      places = [:p_src, :p_snk1, :p_snk2]
      transitions = [:t1, :t2]
      labels = %{t1: "T1", t2: "T2"}
      flow = [{:p_src, :t1}, {:t1, :p_snk1}, {:p_src, :t2}, {:t2, :p_snk2}]

      net = WorkflowNet.new(:p_src, :p_snk1, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "sink"
    end

    test "refuses WF-net when places and transitions overlap (disjointness violation)" do
      places = [:p_src, :shared_node, :p_snk]
      transitions = [:shared_node, :t_finish]
      labels = %{shared_node: "Shared", t_finish: "Finish"}
      flow = [{:p_src, :shared_node}, {:shared_node, :p_snk}, {:p_snk, :t_finish}]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "disjoint"
      assert :shared_node in refusal.evidence.overlapping_nodes
    end

    test "refuses WF-net containing non-bipartite edges (place-to-place and transition-to-transition)" do
      places = [:p_src, :p_a, :p_b, :p_snk]
      transitions = [:t1, :t2]
      labels = %{t1: "T1", t2: "T2"}
      # Flow contains place->place (:p_a -> :p_b) and transition->transition (:t1 -> :t2)
      flow = [
        {:p_src, :t1},
        {:t1, :t2},
        {:t2, :p_a},
        {:p_a, :p_b},
        {:p_b, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "non-bipartite"
      assert not WorkflowNet.bipartite?(net)
    end

    test "refuses WF-net with orphan transition lacking input preset" do
      places = [:p_src, :p_a, :p_snk]
      transitions = [:t1, :t2, :t_orphan]
      labels = %{t1: "T1", t2: "T2", t_orphan: "Orphan"}

      flow = [
        {:p_src, :t1},
        {:t1, :p_a},
        {:p_a, :t2},
        {:t2, :p_snk},
        {:t_orphan, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "empty preset"
      assert :t_orphan in refusal.evidence.transitions_without_preset
    end

    test "refuses WF-net with orphan transition lacking output postset" do
      places = [:p_src, :p_a, :p_snk]
      transitions = [:t1, :t2, :t_dead_end]
      labels = %{t1: "T1", t2: "T2", t_dead_end: "DeadEnd"}

      flow = [
        {:p_src, :t1},
        {:t1, :p_a},
        {:p_a, :t2},
        {:t2, :p_snk},
        {:p_a, :t_dead_end}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "empty postset"
      assert :t_dead_end in refusal.evidence.transitions_without_postset
    end

    test "refuses WF-net with disconnected island node" do
      places = [:p_src, :p_island, :p_snk]
      transitions = [:t1, :t_island]
      labels = %{t1: "T1", t_island: "Island"}

      flow = [
        {:p_src, :t1},
        {:t1, :p_snk},
        {:p_island, :t_island},
        {:t_island, :p_island}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_structure(net)
      assert refusal.code == :REFUSED_INVALID_WORKFLOW_NET
      assert refusal.detail =~ "Disconnected"
      assert :p_island in refusal.evidence.disconnected_nodes or :t_island in refusal.evidence.disconnected_nodes
    end
  end

  describe "2. Mathematical Soundness Failures & Refusals" do
    test "refuses WF-net with dead transition" do
      # In this net, t_dead requires tokens in p_a AND p_b, but only p_a receives a token
      places = [:p_src, :p_a, :p_b, :p_snk]
      transitions = [:t_split, :t_dead, :t_bypass]
      labels = %{t_split: "Split", t_dead: "Dead Task", t_bypass: "Bypass"}

      flow = [
        {:p_src, :t_split},
        {:t_split, :p_a},
        {:p_a, :t_bypass},
        {:t_bypass, :p_snk},
        {:p_a, :t_dead},
        {:p_b, :t_dead},
        {:t_dead, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_soundness(net)
      assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
      assert refusal.detail =~ "Dead transitions"
      assert :t_dead in refusal.evidence.dead_transitions
    end

    test "refuses WF-net with classical deadlock (AND-join after XOR-split)" do
      # XOR-split into p_branch1 OR p_branch2, but AND-join t_join requires BOTH p_branch1 and p_branch2
      places = [:p_src, :p_b1, :p_b2, :p_snk]
      transitions = [:t_xor_1, :t_xor_2, :t_join]
      labels = %{t_xor_1: "Choose Branch 1", t_xor_2: "Choose Branch 2", t_join: "Synchronize"}

      flow = [
        {:p_src, :t_xor_1},
        {:p_src, :t_xor_2},
        {:t_xor_1, :p_b1},
        {:t_xor_2, :p_b2},
        {:p_b1, :t_join},
        {:p_b2, :t_join},
        {:t_join, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert :ok = WorkflowNet.verify_structure(net)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_soundness(net)
      assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
      assert refusal.detail =~ "deadlock" or refusal.detail =~ "Dead transitions"
    end

    test "refuses WF-net with improper completion (XOR-join after AND-split)" do
      # AND-split into both p_a and p_b, but XOR-join allows either to put token in sink
      places = [:p_src, :p_a, :p_b, :p_snk]
      transitions = [:t_and_split, :t_join_a, :t_join_b]
      labels = %{t_and_split: "AND Split", t_join_a: "Finish A", t_join_b: "Finish B"}

      flow = [
        {:p_src, :t_and_split},
        {:t_and_split, :p_a},
        {:t_and_split, :p_b},
        {:p_a, :t_join_a},
        {:t_join_a, :p_snk},
        {:p_b, :t_join_b},
        {:t_join_b, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert :ok = WorkflowNet.verify_structure(net)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_soundness(net)
      assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
      assert refusal.detail =~ "Improper completion" or refusal.detail =~ "1-Safety"
    end

    test "refuses WF-net with livelock (inescapable loop with no exit to sink)" do
      transitions = [:t_init, :t_step1, :t_step2, :t_orphan_sink]
      labels = %{t_init: "Init", t_step1: "Cycle 1", t_step2: "Cycle 2", t_orphan_sink: "Never Reachable"}
      places_closed = [:p_src, :p_loop1, :p_loop2, :p_unmarked, :p_snk]

      flow_closed = [
        {:p_src, :t_init},
        {:t_init, :p_loop1},
        {:p_loop1, :t_step1},
        {:t_step1, :p_loop2},
        {:p_loop2, :t_step2},
        {:t_step2, :p_loop1},
        {:p_unmarked, :t_orphan_sink},
        {:t_orphan_sink, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places_closed, transitions, labels, flow_closed)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_soundness(net)
      assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
    end

    test "refuses WF-net violating 1-safety via unsafe concurrent merge" do
      # AND-split sends tokens to p_a and p_b; transitions t_a and t_b both deposit tokens into p_common
      # causing p_common to accumulate 2 tokens!
      places = [:p_src, :p_a, :p_b, :p_common, :p_snk]
      transitions = [:t_split, :t_a, :t_b, :t_finish]
      labels = %{t_split: "Split", t_a: "A", t_b: "B", t_finish: "Finish"}

      flow = [
        {:p_src, :t_split},
        {:t_split, :p_a},
        {:t_split, :p_b},
        {:p_a, :t_a},
        {:t_a, :p_common},
        {:p_b, :t_b},
        {:t_b, :p_common},
        {:p_common, :t_finish},
        {:t_finish, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert :ok = WorkflowNet.verify_structure(net)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_soundness(net)
      assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
      assert refusal.detail =~ "1-Safety violated"
      assert refusal.evidence.place == :p_common
    end

    test "refuses WF-net when state space explosion exceeds max_markings limit" do
      # Linear net with option max_markings: 1
      places = [:p_src, :p_a, :p_b, :p_snk]
      transitions = [:t1, :t2, :t3]
      labels = %{t1: "1", t2: "2", t3: "3"}
      flow = [{:p_src, :t1}, {:t1, :p_a}, {:p_a, :t2}, {:t2, :p_b}, {:p_b, :t3}, {:t3, :p_snk}]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert {:error, %Refusal{} = refusal} = WorkflowNet.verify_soundness(net, max_markings: 2)
      assert refusal.code == :REFUSED_UNSOUND_WORKFLOW_NET
      assert refusal.detail =~ "State explosion" or refusal.evidence[:cutoff] == :max_markings
    end
  end

  describe "3. Certified Sound and Separable Workflow Nets" do
    test "proves soundness for strict sequential workflow net" do
      places = [:p_src, :p_step1, :p_step2, :p_snk]
      transitions = [:t_step1, :t_step2, :t_step3]
      labels = %{t_step1: "Step 1", t_step2: "Step 2", t_step3: "Step 3"}

      flow = [
        {:p_src, :t_step1},
        {:t_step1, :p_step1},
        {:p_step1, :t_step2},
        {:t_step2, :p_step2},
        {:p_step2, :t_step3},
        {:t_step3, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert WorkflowNet.bipartite?(net) == true
      assert :ok = WorkflowNet.verify_structure(net)
      assert :ok = WorkflowNet.verify_soundness(net)
      assert WorkflowNet.state_machine?(net) == true
      assert WorkflowNet.marked_graph?(net) == true
    end

    test "proves soundness for concurrent diamond (Marked Graph)" do
      places_clean = [:p_src, :p_a, :p_b, :p_a_done, :p_b_done, :p_snk]
      transitions = [:t_and_split, :t_task_a, :t_task_b, :t_and_join]

      labels = %{
        t_and_split: "Fork",
        t_task_a: "Task Alpha",
        t_task_b: "Task Beta",
        t_and_join: "Join"
      }

      flow_clean = [
        {:p_src, :t_and_split},
        {:t_and_split, :p_a},
        {:t_and_split, :p_b},
        {:p_a, :t_task_a},
        {:p_b, :t_task_b},
        {:t_task_a, :p_a_done},
        {:t_task_b, :p_b_done},
        {:p_a_done, :t_and_join},
        {:p_b_done, :t_and_join},
        {:t_and_join, :p_snk}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places_clean, transitions, labels, flow_clean)
      assert :ok = WorkflowNet.verify_structure(net)
      assert :ok = WorkflowNet.verify_soundness(net)
      assert WorkflowNet.marked_graph?(net) == true
    end

    test "proves soundness for exclusive choice with retry loop (State Machine)" do
      places = [:p_src, :p_choose, :p_snk]
      transitions = [:t_init, :t_approve, :t_reject_retry]

      labels = %{
        t_init: "Submit Order",
        t_approve: "Approve Order",
        t_reject_retry: "Reject & Retry"
      }

      flow = [
        {:p_src, :t_init},
        {:t_init, :p_choose},
        {:p_choose, :t_approve},
        {:t_approve, :p_snk},
        {:p_choose, :t_reject_retry},
        {:t_reject_retry, :p_choose}
      ]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)
      assert :ok = WorkflowNet.verify_structure(net)
      assert :ok = WorkflowNet.verify_soundness(net)
      assert WorkflowNet.state_machine?(net) == true
    end
  end
end
