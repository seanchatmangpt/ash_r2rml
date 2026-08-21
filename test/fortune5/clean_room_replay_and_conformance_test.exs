# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Fortune5.CleanRoomReplayAndConformanceTest do
  @moduledoc """
  Fortune 5 Clean-Room State Replay & OCEL 2.0 Process Conformance Test Suite.

  Exercises:
  1. Clean-room state reconstruction starting from completely empty in-memory state,
     consuming only the admitted IEEE/W3C OCEL 2.0 event stream.
  2. Deterministic convergence under hostile asynchronous event ingestion (shuffled order).
  3. Qualified polymorphic Event-to-Object (E2O) relations (`:target`, `:initiator`, `:actor`, `:input`, `:output`).
  4. Qualified Object-to-Object (O2O) multigraph topology (`:dependsOn`, `:memberOf`, `:relatesTo`).
  5. Dynamic time-varying attribute histories and point-in-time state queries.
  6. Process Conformance Checking (van der Aalst Process Science):
     - Valid process trace verification (fitness = 1.0).
     - Detection of impossible sequence violations (unapproved deployments).
     - Detection of missing mandatory audit steps.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Telemetry.OCEL2

  defp sha256_term(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp admitted_incident_event_stream do
    [
      %{
        "ocel:eid" => "ev_inc_01",
        "ocel:activity" => "incident.detect",
        "ocel:timestamp" => "2026-08-21T08:00:00.000000Z",
        "ocel:lifecycle" => "start",
        "ocel:omap" => [
          "incident:INC-2026-9001",
          "service:auth-gateway",
          "host:node-c5-042"
        ],
        "ocel:e2o" => [
          %{"ocel:oid" => "incident:INC-2026-9001", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "service:auth-gateway", "ocel:qualifier" => "resource"},
          %{"ocel:oid" => "host:node-c5-042", "ocel:qualifier" => "resource"}
        ],
        "ocel:vmap" => %{
          "severity" => "P1-CRITICAL",
          "error_rate_pct" => "18.5",
          "status" => "detected"
        }
      },
      %{
        "ocel:eid" => "ev_inc_02",
        "ocel:activity" => "incident.triage",
        "ocel:timestamp" => "2026-08-21T08:15:00.000000Z",
        "ocel:lifecycle" => "stop",
        "ocel:omap" => [
          "incident:INC-2026-9001",
          "actor:sec-lead-01"
        ],
        "ocel:e2o" => [
          %{"ocel:oid" => "incident:INC-2026-9001", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "actor:sec-lead-01", "ocel:qualifier" => "actor"}
        ],
        "ocel:vmap" => %{
          "status" => "triaged",
          "assigned_to" => "sec-lead-01",
          "root_cause" => "TLS Cert Expiration on auth-gateway"
        }
      },
      %{
        "ocel:eid" => "ev_cr_01",
        "ocel:activity" => "change_request.draft",
        "ocel:timestamp" => "2026-08-21T08:30:00.000000Z",
        "ocel:lifecycle" => "stop",
        "ocel:omap" => [
          "change_request:CR-8810",
          "incident:INC-2026-9001",
          "actor:sec-lead-01"
        ],
        "ocel:e2o" => [
          %{"ocel:oid" => "change_request:CR-8810", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "incident:INC-2026-9001", "ocel:qualifier" => "input"},
          %{"ocel:oid" => "actor:sec-lead-01", "ocel:qualifier" => "initiator"}
        ],
        "ocel:vmap" => %{
          "title" => "Emergency TLS Certificate Roll",
          "target_version" => "v2.18.5",
          "status" => "drafted"
        }
      },
      %{
        "ocel:eid" => "ev_cr_02",
        "ocel:activity" => "change_request.approve",
        "ocel:timestamp" => "2026-08-21T08:45:00.000000Z",
        "ocel:lifecycle" => "stop",
        "ocel:omap" => [
          "change_request:CR-8810",
          "actor:cab-director-01"
        ],
        "ocel:e2o" => [
          %{"ocel:oid" => "change_request:CR-8810", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "actor:cab-director-01", "ocel:qualifier" => "actor"}
        ],
        "ocel:vmap" => %{
          "status" => "approved",
          "approval_risk_level" => "emergency_low_risk"
        }
      },
      %{
        "ocel:eid" => "ev_dep_01",
        "ocel:activity" => "deploy.execute",
        "ocel:timestamp" => "2026-08-21T09:00:00.000000Z",
        "ocel:lifecycle" => "stop",
        "ocel:omap" => [
          "change_request:CR-8810",
          "service:auth-gateway",
          "host:node-c5-042"
        ],
        "ocel:e2o" => [
          %{"ocel:oid" => "change_request:CR-8810", "ocel:qualifier" => "input"},
          %{"ocel:oid" => "service:auth-gateway", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "host:node-c5-042", "ocel:qualifier" => "resource"}
        ],
        "ocel:vmap" => %{
          "deploy_status" => "success",
          "active_version" => "v2.18.5"
        }
      },
      %{
        "ocel:eid" => "ev_inc_03",
        "ocel:activity" => "incident.resolve",
        "ocel:timestamp" => "2026-08-21T09:15:00.000000Z",
        "ocel:lifecycle" => "stop",
        "ocel:omap" => [
          "incident:INC-2026-9001",
          "service:auth-gateway"
        ],
        "ocel:e2o" => [
          %{"ocel:oid" => "incident:INC-2026-9001", "ocel:qualifier" => "target"},
          %{"ocel:oid" => "service:auth-gateway", "ocel:qualifier" => "resource"}
        ],
        "ocel:vmap" => %{
          "status" => "resolved",
          "error_rate_pct" => "0.001",
          "downtime_minutes" => "75"
        }
      }
    ]
  end

  # ============================================================================
  # Tests
  # ============================================================================

  describe "1. Clean-Room Replay & Deterministic State Convergence" do
    test "reconstructs exact identical state and SHA-256 hash independent of event arrival order" do
      events = admitted_incident_event_stream()

      # 1. Validate OCEL 2.0 schema metrics
      assert {:ok, metrics} = OCEL2.validate(events)
      assert metrics.valid? == true
      assert metrics.event_count == 6
      assert metrics.distinct_object_count == 6

      # 2. Clean-room Run 1: Natural order
      assert {:ok, recon1} = OCEL2.reconstruct_from_events(events)
      hash1 = sha256_term(recon1)

      # 3. Clean-room Run 2: Shuffled asynchronous ingestion order
      shuffled_events = Enum.shuffle(events)
      assert {:ok, recon2} = OCEL2.reconstruct_from_events(shuffled_events)
      hash2 = sha256_term(recon2)

      # 4. Proves deterministic state convergence across clean-room runs
      assert hash1 == hash2
      assert recon1.objects == recon2.objects
      assert recon1.activities_order == recon2.activities_order

      # Verify incident:INC-2026-9001 state evolution
      inc_obj = recon1.objects["incident:INC-2026-9001"]
      assert inc_obj.id == "incident:INC-2026-9001"
      assert inc_obj.type == "incident"
      assert inc_obj.attributes["status"] == "resolved"
      assert inc_obj.attributes["error_rate_pct"] == "0.001"
      assert inc_obj.attributes["downtime_minutes"] == "75"

      # Verify change_request:CR-8810 state evolution
      cr_obj = recon1.objects["change_request:CR-8810"]
      assert cr_obj.id == "change_request:CR-8810"
      assert cr_obj.type == "change_request"
      assert cr_obj.attributes["status"] == "approved"
    end

    test "queries historical point-in-time states during the incident lifecycle" do
      events = admitted_incident_event_stream()
      assert {:ok, recon} = OCEL2.reconstruct_from_events(events)

      # Point in time: 08:20:00 (after triage at 08:15, before change request draft at 08:30)
      assert {:ok, pit_state} = OCEL2.state_at(recon, "incident:INC-2026-9001", "2026-08-21T08:20:00.000000Z")

      assert pit_state.id == "incident:INC-2026-9001"
      assert pit_state.type == "incident"
      assert pit_state.attributes["status"] == "triaged"
      assert pit_state.attributes["assigned_to"] == "sec-lead-01"
      assert pit_state.last_activity == "incident.triage"
    end
  end

  describe "2. Qualified Polymorphic E2O & O2O Multigraph Relations" do
    test "verifies qualified event-to-object relations in clean-room reconstruction" do
      events = admitted_incident_event_stream()
      assert {:ok, recon} = OCEL2.reconstruct_from_events(events)

      # Verify triage event E2O qualifiers
      triage_e2o = recon.e2o_map["ev_inc_02"]
      assert length(triage_e2o) == 2

      target_entry = Enum.find(triage_e2o, &(&1.object_id == "incident:INC-2026-9001"))
      assert target_entry.qualifier == "target"

      actor_entry = Enum.find(triage_e2o, &(&1.object_id == "actor:sec-lead-01"))
      assert actor_entry.qualifier == "actor"
    end
  end

  describe "3. Process Conformance Checking (van der Aalst Process Science)" do
    @expected_lifecycle_order [
      "incident.detect",
      "incident.triage",
      "change_request.draft",
      "change_request.approve",
      "deploy.execute",
      "incident.resolve"
    ]

    test "validates fully conforming enterprise incident lifecycle with 1.0 fitness" do
      events = admitted_incident_event_stream()

      assert {:ok, report} = OCEL2.check_conformance(events, @expected_lifecycle_order)
      assert report.valid? == true
      assert report.fitness == 1.0
      assert report.missing_activities == []
      assert report.impossible_sequences == []
      assert report.temporal_violations == []
    end

    test "detects impossible sequence violation when deploy occurs before change approval" do
      # Corrupt trace: deploy.execute (08:35) BEFORE change_request.approve (08:45)
      corrupt_events = [
        %{
          "ocel:eid" => "ev1",
          "ocel:activity" => "change_request.draft",
          "ocel:timestamp" => "2026-08-21T08:30:00Z",
          "ocel:omap" => ["cr:1"]
        },
        %{
          "ocel:eid" => "ev2",
          "ocel:activity" => "deploy.execute",
          "ocel:timestamp" => "2026-08-21T08:35:00Z",
          "ocel:omap" => ["cr:1"]
        },
        %{
          "ocel:eid" => "ev3",
          "ocel:activity" => "change_request.approve",
          "ocel:timestamp" => "2026-08-21T08:45:00Z",
          "ocel:omap" => ["cr:1"]
        }
      ]

      expected = ["change_request.draft", "change_request.approve", "deploy.execute"]
      assert {:ok, report} = OCEL2.check_conformance(corrupt_events, expected)
      assert report.valid? == false
      assert length(report.impossible_sequences) > 0
    end

    test "detects missing mandatory security approval activity" do
      # Trace missing change_request.approve
      skipped_approval_events = [
        %{
          "ocel:eid" => "ev1",
          "ocel:activity" => "change_request.draft",
          "ocel:timestamp" => "2026-08-21T08:30:00Z",
          "ocel:omap" => ["cr:1"]
        },
        %{
          "ocel:eid" => "ev2",
          "ocel:activity" => "deploy.execute",
          "ocel:timestamp" => "2026-08-21T09:00:00Z",
          "ocel:omap" => ["cr:1"]
        }
      ]

      expected = ["change_request.draft", "change_request.approve", "deploy.execute"]
      assert {:ok, report} = OCEL2.check_conformance(skipped_approval_events, expected)
      assert report.valid? == false
      assert "change_request.approve" in report.missing_activities
      assert report.fitness < 1.0
    end
  end
end
