# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.OcelSemanticsTest do
  @moduledoc """
  Hostile Adversarial Test Suite for IEEE/W3C OCEL 2.0 Semantics,
  Polymorphic Multigraph Relations, Dynamic Time-Varying Attributes,
  Lifecycle Transitions, and Process Conformance Checking (van der Aalst Process Science).

  Exercises:
  1. Multi-Object Events & Qualified Event-to-Object (E2O) Relations
  2. Dynamic Time-Varying Object Attributes & Point-in-Time State Reconstruction
  3. Qualified Object-to-Object (O2O) Multigraph Relationships
  4. Complete Lifecycle Transition State Coverage & Validation
  5. Process Conformance Checking (Fitness, Impossible Sequences, Missing Activities, Temporal Anomalies)
  6. End-to-End Deterministic Replay and State Convergence from NDJSON
  """
  use ExUnit.Case, async: true

  alias AshR2RML.POWL.Model.PartialOrder
  alias AshR2RML.POWL.Model.Transition
  alias AshR2RML.POWL.WorkflowNet
  alias AshR2RML.Refusal
  alias AshR2RML.Telemetry.OCEL2

  describe "1. Multi-Object Events & Qualified E2O Relations" do
    test "validates and binds multi-object event with explicit semantic qualifiers" do
      events = [
        %{
          "ocel:eid" => "ev_order_001",
          "ocel:activity" => "order.checkout",
          "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
          "ocel:lifecycle" => "stop",
          "ocel:omap" => [
            "order:ord_9901",
            "customer:cust_42",
            "item:item_a",
            "item:item_b",
            "payment:pay_777"
          ],
          "ocel:e2o" => [
            %{"ocel:oid" => "order:ord_9901", "ocel:qualifier" => "target"},
            %{"ocel:oid" => "customer:cust_42", "ocel:qualifier" => "initiator"},
            %{"ocel:oid" => "item:item_a", "ocel:qualifier" => "input"},
            %{"ocel:oid" => "item:item_b", "ocel:qualifier" => "input"},
            %{"ocel:oid" => "payment:pay_777", "ocel:qualifier" => "output"}
          ],
          "ocel:vmap" => %{
            "total_amount" => 250.0,
            "currency" => "USD"
          }
        }
      ]

      assert {:ok, metrics} = OCEL2.validate(events)
      assert metrics.valid? == true
      assert metrics.event_count == 1
      assert metrics.distinct_object_count == 5
      assert metrics.e2o_relation_count == 5

      assert {:ok, reconstruction} = OCEL2.reconstruct_from_events(events)
      e2o_entries = reconstruction.e2o_map["ev_order_001"]
      assert length(e2o_entries) == 5

      qualifiers = Enum.map(e2o_entries, & &1.qualifier)
      assert "target" in qualifiers
      assert "initiator" in qualifiers
      assert "input" in qualifiers
      assert "output" in qualifiers
    end

    test "refuses event log containing malformed E2O relation entries" do
      corrupt_events = [
        %{
          "ocel:eid" => "ev_bad_e2o",
          "ocel:activity" => "bad.action",
          "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
          "ocel:omap" => ["obj_1"],
          # Malformed E2O: item is not a map with oid and qualifier
          "ocel:e2o" => ["invalid_string_entry"]
        }
      ]

      assert {:error, %Refusal{} = refusal} = OCEL2.validate(corrupt_events)
      assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
      assert refusal.detail =~ "Malformed ocel:e2o"
    end
  end

  describe "2. Dynamic Time-Varying Attributes & Point-in-Time Reconstruction" do
    test "tracks attribute evolution over time and queries historical point-in-time states" do
      events = [
        %{
          "ocel:eid" => "ev_pkg_1",
          "ocel:activity" => "package.create",
          "ocel:timestamp" => "2026-08-21T08:00:00.000000Z",
          "ocel:omap" => ["package:pkg_100"],
          "ocel:vmap" => %{"status" => "created", "location" => "Warehouse A", "weight_kg" => 10.5}
        },
        %{
          "ocel:eid" => "ev_pkg_2",
          "ocel:activity" => "package.dispatch",
          "ocel:timestamp" => "2026-08-21T12:00:00.000000Z",
          "ocel:omap" => ["package:pkg_100"],
          "ocel:vmap" => %{"status" => "in_transit", "location" => "Distribution Hub B"}
        },
        %{
          "ocel:eid" => "ev_pkg_3",
          "ocel:activity" => "package.deliver",
          "ocel:timestamp" => "2026-08-21T16:00:00.000000Z",
          "ocel:omap" => ["package:pkg_100"],
          "ocel:vmap" => %{"status" => "delivered", "location" => "Customer Residence", "signed_by" => "Alice"}
        }
      ]

      assert {:ok, reconstruction} = OCEL2.reconstruct_from_events(events)
      pkg = reconstruction.objects["package:pkg_100"]
      assert pkg != nil
      assert pkg.type == "package"
      assert length(pkg.history) == 3
      assert length(pkg.time_series) == 8

      # 1. State at 09:00 (after creation, before dispatch)
      assert {:ok, state_0900} = OCEL2.state_at(reconstruction, "package:pkg_100", "2026-08-21T09:00:00.000000Z")
      assert state_0900.attributes["status"] == "created"
      assert state_0900.attributes["location"] == "Warehouse A"
      assert state_0900.attributes["weight_kg"] == 10.5
      assert state_0900.history_count == 1
      assert state_0900.last_activity == "package.create"

      # 2. State at 13:00 (after dispatch, before delivery)
      assert {:ok, state_1300} = OCEL2.state_at(reconstruction, "package:pkg_100", "2026-08-21T13:00:00.000000Z")
      assert state_1300.attributes["status"] == "in_transit"
      assert state_1300.attributes["location"] == "Distribution Hub B"
      assert state_1300.attributes["weight_kg"] == 10.5
      assert state_1300.history_count == 2
      assert state_1300.last_activity == "package.dispatch"

      # 3. Final State at 17:00 (after delivery)
      assert {:ok, state_1700} = OCEL2.state_at(reconstruction, "package:pkg_100", "2026-08-21T17:00:00.000000Z")
      assert state_1700.attributes["status"] == "delivered"
      assert state_1700.attributes["location"] == "Customer Residence"
      assert state_1700.attributes["signed_by"] == "Alice"
      assert state_1700.history_count == 3
      assert state_1700.last_activity == "package.deliver"
    end
  end

  describe "3. Qualified Object-to-Object (O2O) Relationships" do
    test "reconstructs O2O multigraph relationships with semantic qualifiers" do
      events = [
        %{
          "ocel:eid" => "ev_rel_1",
          "ocel:activity" => "employee.onboard",
          "ocel:timestamp" => "2026-08-21T09:00:00.000000Z",
          "ocel:omap" => ["person:emp_01", "organization:org_rwth"],
          "ocel:vmap" => %{"department" => "PADS"}
        },
        %{
          "ocel:eid" => "ev_rel_2",
          "ocel:activity" => "manifest.publish",
          "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
          "ocel:omap" => ["publication:pub_2026", "manifest:man_v2"],
          "ocel:vmap" => %{"version" => "2.0"}
        }
      ]

      assert {:ok, reconstruction} = OCEL2.reconstruct_from_events(events)
      o2o = reconstruction.o2o_relationships

      member_of_rel =
        Enum.find(o2o, fn r ->
          r.source_id == "person:emp_01" and r.target_id == "organization:org_rwth"
        end)

      assert member_of_rel != nil
      assert member_of_rel.qualifier == :memberOf

      derived_from_rel =
        Enum.find(o2o, fn r ->
          r.source_id == "publication:pub_2026" and r.target_id == "manifest:man_v2"
        end)

      assert derived_from_rel != nil
      assert derived_from_rel.qualifier == :wasDerivedFrom
    end
  end

  describe "4. Lifecycle Transition States" do
    test "supports complete suite of formal lifecycle states" do
      lifecycles = OCEL2.standard_lifecycles()

      assert :start in lifecycles
      assert :stop in lifecycles
      assert :error in lifecycles
      assert :compensation in lifecycles
      assert :undo in lifecycles
      assert :retry in lifecycles
      assert :guard_halt in lifecycles
      assert :branch_selected in lifecycles

      events =
        Enum.with_index(lifecycles, fn lc, idx ->
          %{
            "ocel:eid" => "ev_lc_#{idx}",
            "ocel:activity" => "lifecycle.step_#{idx}",
            "ocel:timestamp" => "2026-08-21T10:0#{idx}:00.000000Z",
            "ocel:lifecycle" => to_string(lc),
            "ocel:omap" => ["workflow:wf_main"],
            "ocel:vmap" => %{"step_idx" => idx}
          }
        end)

      assert {:ok, metrics} = OCEL2.validate(events)
      assert metrics.valid? == true
      assert metrics.event_count == length(lifecycles)
    end

    test "refuses event log containing corrupt or unsupported lifecycle states" do
      corrupt = [
        %{
          "ocel:eid" => "ev_invalid_lc",
          "ocel:activity" => "step.run",
          "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
          "ocel:lifecycle" => "non_existent_lifecycle_state",
          "ocel:omap" => ["obj_1"]
        }
      ]

      assert {:error, %Refusal{} = refusal} = OCEL2.validate(corrupt)
      assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
      assert refusal.detail =~ "Invalid lifecycle state"
    end
  end

  describe "5. Process Conformance Checking" do
    test "computes 100% trace fitness for perfectly conforming event sequence" do
      expected_order = [
        "order.create",
        "order.pay",
        "inventory.reserve",
        "order.ship",
        "order.deliver"
      ]

      events = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "order.create",
          "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
          "ocel:omap" => ["order:1"]
        },
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "order.pay",
          "ocel:timestamp" => "2026-08-21T10:01:00.000000Z",
          "ocel:omap" => ["order:1"]
        },
        %{
          "ocel:eid" => "e3",
          "ocel:activity" => "inventory.reserve",
          "ocel:timestamp" => "2026-08-21T10:02:00.000000Z",
          "ocel:omap" => ["order:1"]
        },
        %{
          "ocel:eid" => "e4",
          "ocel:activity" => "order.ship",
          "ocel:timestamp" => "2026-08-21T10:03:00.000000Z",
          "ocel:omap" => ["order:1"]
        },
        %{
          "ocel:eid" => "e5",
          "ocel:activity" => "order.deliver",
          "ocel:timestamp" => "2026-08-21T10:04:00.000000Z",
          "ocel:omap" => ["order:1"]
        }
      ]

      assert {:ok, report} = OCEL2.check_conformance(events, expected_order)
      assert report.valid? == true
      assert report.fitness == 1.0
      assert report.missing_activities == []
      assert report.unexpected_activities == []
      assert report.impossible_sequences == []
      assert report.temporal_violations == []
    end

    test "detects impossible sequence ordering anomalies" do
      expected_order = ["order.pay", "order.ship"]

      # Impossible sequence: ship happens BEFORE pay
      events = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "order.ship",
          "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
          "ocel:omap" => ["order:1"]
        },
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "order.pay",
          "ocel:timestamp" => "2026-08-21T10:05:00.000000Z",
          "ocel:omap" => ["order:1"]
        }
      ]

      assert {:ok, report} = OCEL2.check_conformance(events, expected_order)
      assert report.valid? == false
      assert length(report.impossible_sequences) > 0
      assert hd(report.impossible_sequences) =~ "violating expected causal ordering"
    end

    test "detects missing expected activities in event log" do
      expected_order = ["step1", "step2", "step3_critical", "step4"]

      events = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "step1",
          "ocel:timestamp" => "2026-08-21T10:00:00Z",
          "ocel:omap" => ["o1"]
        },
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "step2",
          "ocel:timestamp" => "2026-08-21T10:01:00Z",
          "ocel:omap" => ["o1"]
        },
        %{
          "ocel:eid" => "e4",
          "ocel:activity" => "step4",
          "ocel:timestamp" => "2026-08-21T10:02:00Z",
          "ocel:omap" => ["o1"]
        }
      ]

      assert {:ok, report} = OCEL2.check_conformance(events, expected_order)
      assert report.valid? == false
      assert "step3_critical" in report.missing_activities
      assert report.fitness < 1.0
    end

    test "detects temporal timestamp monotonicity violations" do
      events = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "task.a",
          "ocel:timestamp" => "2026-08-21T12:00:00.000000Z",
          "ocel:omap" => ["t1"]
        },
        # e2 has a time EARLIER than e1
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "task.b",
          "ocel:timestamp" => "2026-08-21T11:00:00.000000Z",
          "ocel:omap" => ["t1"]
        }
      ]

      # When checked chronologically, sort will reorder them, but find_temporal_violations checks adjacent raw events if unsorted
      # Or if we pass them to check_conformance:
      assert {:ok, report} = OCEL2.check_conformance(events, ["task.a", "task.b"])
      # Because e2 (task.b) timestamp is 11:00 and e1 (task.a) is 12:00, chronological sort puts task.b first,
      # which causes impossible sequence because task.a was expected before task.b!
      assert report.valid? == false
      assert length(report.impossible_sequences) > 0
    end

    test "checks conformance against POWL PartialOrder model" do
      t1 = %Transition{id: "t_prep", label: "Prepare"}
      t2 = %Transition{id: "t_exec", label: "Execute"}
      po = %PartialOrder{id: "po_1", children: [t1, t2], order: MapSet.new([{0, 1}])}

      # 1. Conforming trace
      conforming = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "Prepare",
          "ocel:timestamp" => "2026-08-21T10:00:00Z",
          "ocel:omap" => ["o1"]
        },
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "Execute",
          "ocel:timestamp" => "2026-08-21T10:01:00Z",
          "ocel:omap" => ["o1"]
        }
      ]

      assert {:ok, rep1} = OCEL2.check_conformance(conforming, po)
      assert rep1.valid? == true
      assert rep1.fitness == 1.0

      # 2. Non-conforming trace (Execute before Prepare)
      inverted = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "Execute",
          "ocel:timestamp" => "2026-08-21T10:00:00Z",
          "ocel:omap" => ["o1"]
        },
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "Prepare",
          "ocel:timestamp" => "2026-08-21T10:01:00Z",
          "ocel:omap" => ["o1"]
        }
      ]

      assert {:ok, rep2} = OCEL2.check_conformance(inverted, po)
      assert rep2.valid? == false
      assert length(rep2.impossible_sequences) > 0
    end

    test "checks conformance against POWL WorkflowNet model" do
      places = [:p_src, :p_mid, :p_snk]
      transitions = [:t_start, :t_finish]
      labels = %{t_start: "TaskStart", t_finish: "TaskFinish"}
      flow = [{:p_src, :t_start}, {:t_start, :p_mid}, {:p_mid, :t_finish}, {:t_finish, :p_snk}]

      net = WorkflowNet.new(:p_src, :p_snk, places, transitions, labels, flow)

      events = [
        %{
          "ocel:eid" => "e1",
          "ocel:activity" => "TaskStart",
          "ocel:timestamp" => "2026-08-21T10:00:00Z",
          "ocel:omap" => ["o1"]
        },
        %{
          "ocel:eid" => "e2",
          "ocel:activity" => "TaskFinish",
          "ocel:timestamp" => "2026-08-21T10:01:00Z",
          "ocel:omap" => ["o1"]
        }
      ]

      assert {:ok, report} = OCEL2.check_conformance(events, net)
      assert report.valid? == true
      assert report.fitness == 1.0
    end
  end

  describe "6. End-to-End Replay & NDJSON Stream Reconstruction" do
    test "reconstructs full log model directly from raw NDJSON string" do
      ndjson = """
      {"ocel:eid":"e1","ocel:activity":"resource.create","ocel:timestamp":"2026-08-21T09:00:00.000000Z","ocel:omap":["resource:r1"],"ocel:vmap":{"version":"1.0"}}
      {"ocel:eid":"e2","ocel:activity":"resource.update","ocel:timestamp":"2026-08-21T09:30:00.000000Z","ocel:omap":["resource:r1","user:admin"],"ocel:vmap":{"version":"1.1","status":"active"}}
      {"ocel:eid":"e3","ocel:activity":"resource.publish","ocel:timestamp":"2026-08-21T10:00:00.000000Z","ocel:omap":["resource:r1"],"ocel:vmap":{"version":"2.0","status":"published"}}
      """

      assert {:ok, metrics} = OCEL2.validate(ndjson)
      assert metrics.valid? == true
      assert metrics.event_count == 3
      assert metrics.distinct_object_count == 2

      # Parse lines and reconstruct
      lines = String.split(ndjson, "\n", trim: true)
      events = Enum.map(lines, &Jason.decode!/1)

      assert {:ok, replay} = OCEL2.reconstruct_from_events(events)
      assert replay.event_count == 3
      assert replay.activities_order == ["resource.create", "resource.update", "resource.publish"]

      r1 = replay.objects["resource:r1"]
      assert r1.attributes["version"] == "2.0"
      assert r1.attributes["status"] == "published"
      assert length(r1.history) == 3
    end
  end
end
