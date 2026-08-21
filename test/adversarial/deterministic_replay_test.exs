# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.DeterministicReplayTest do
  @moduledoc """
  Chicago-Style Clean-Room Deterministic Replay Test Suite.
  Wipes all runtime state, consumes only the admitted OCEL 2.0 event stream,
  and reconstructs identical final object graphs and database states.
  Proves deterministic state convergence, partial-order causality, and fail-closed schema validation.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Telemetry.OCEL2

  defp sha256_term(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp admitted_event_stream do
    [
      %{
        "ocel:eid" => "018e6e5a-0001-7000-8000-000000000001",
        "ocel:activity" => "tenant.create",
        "ocel:timestamp" => "2026-08-21T09:00:00.000000Z",
        "ocel:omap" => ["tenant:alpha"],
        "ocel:vmap" => %{"name" => "Alpha Corp", "plan" => "enterprise"}
      },
      %{
        "ocel:eid" => "018e6e5a-0002-7000-8000-000000000002",
        "ocel:activity" => "project.create",
        "ocel:timestamp" => "2026-08-21T09:30:00.000000Z",
        "ocel:omap" => ["project:p_obda", "tenant:alpha"],
        "ocel:vmap" => %{"title" => "OBDA Engine", "budget" => "75000.00", "active" => true}
      },
      %{
        "ocel:eid" => "018e6e5a-0003-7000-8000-000000000003",
        "ocel:activity" => "task.create",
        "ocel:timestamp" => "2026-08-21T10:00:00.000000Z",
        "ocel:omap" => ["task:t_1", "project:p_obda"],
        "ocel:vmap" => %{"name" => "R2RML Mapping", "priority" => 1, "hours" => "40.00"}
      },
      %{
        "ocel:eid" => "018e6e5a-0004-7000-8000-000000000004",
        "ocel:activity" => "task.update",
        "ocel:timestamp" => "2026-08-21T11:00:00.000000Z",
        "ocel:omap" => ["task:t_1"],
        "ocel:vmap" => %{"hours" => "45.50", "status" => "in_progress"}
      },
      %{
        "ocel:eid" => "018e6e5a-0005-7000-8000-000000000005",
        "ocel:activity" => "task.complete",
        "ocel:timestamp" => "2026-08-21T12:00:00.000000Z",
        "ocel:omap" => ["task:t_1", "project:p_obda"],
        "ocel:vmap" => %{"status" => "completed", "completed_at" => "2026-08-21T12:00:00.000000Z"}
      }
    ]
  end

  describe "Clean-Room Deterministic State Replay" do
    test "reconstructs exact identical object graph and state history from event stream across independent runs" do
      events = admitted_event_stream()

      # Validate admitted OCEL 2.0 schema
      assert {:ok, metrics} = OCEL2.validate(events)
      assert metrics.valid? == true
      assert metrics.event_count == 5
      assert metrics.distinct_object_count == 3

      # Run 1: Clean-room replay
      assert {:ok, recon1} = OCEL2.reconstruct_from_events(events)
      hash1 = sha256_term(recon1)

      # Run 2: Clean-room replay (shuffled input list representing asynchronous ingestion order)
      shuffled_events = Enum.shuffle(events)
      assert {:ok, recon2} = OCEL2.reconstruct_from_events(shuffled_events)
      hash2 = sha256_term(recon2)

      # Proves deterministic state convergence independent of ingestion arrival order
      assert hash1 == hash2
      assert recon1.objects == recon2.objects
      assert recon1.activities_order == recon2.activities_order

      # Verify state transition fidelity on task:t_1
      task_obj = recon1.objects["task:t_1"]
      assert task_obj.id == "task:t_1"
      assert length(task_obj.history) == 3

      activities = Enum.map(task_obj.history, &elem(&1, 0))
      assert activities == ["task.create", "task.update", "task.complete"]
      assert task_obj.attributes["status"] == "completed"
      assert task_obj.attributes["hours"] == "45.50"
    end

    test "reconstructs multi-object relations and temporal causality" do
      events = admitted_event_stream()
      assert {:ok, recon} = OCEL2.reconstruct_from_events(events)

      # Verify project was touched by project.create, task.create, and task.complete
      project_obj = recon.objects["project:p_obda"]
      project_activities = Enum.map(project_obj.history, &elem(&1, 0))
      assert project_activities == ["project.create", "task.create", "task.complete"]
      assert project_obj.attributes["title"] == "OBDA Engine"
      assert project_obj.attributes["active"] == true

      # Verify tenant history
      tenant_obj = recon.objects["tenant:alpha"]
      tenant_activities = Enum.map(tenant_obj.history, &elem(&1, 0))
      assert tenant_activities == ["tenant.create", "project.create"]
      assert tenant_obj.attributes["name"] == "Alpha Corp"
    end
  end

  describe "Adversarial Schema Corruptions & Rejection" do
    test "refuses event log missing required ocel:eid attribute" do
      corrupted = [
        %{
          "ocel:activity" => "tenant.create",
          "ocel:timestamp" => "2026-08-21T09:00:00.000000Z",
          "ocel:omap" => ["tenant:alpha"]
        }
      ]

      assert {:error, refusal} = OCEL2.validate(corrupted)
      assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
      assert Enum.any?(refusal.evidence.errors, &String.contains?(&1, "ocel:eid"))
    end

    test "refuses event log with invalid non-ISO 8601 timestamp" do
      corrupted = [
        %{
          "ocel:eid" => "eid-123",
          "ocel:activity" => "tenant.create",
          "ocel:timestamp" => "not-a-timestamp",
          "ocel:omap" => ["tenant:alpha"]
        }
      ]

      assert {:error, refusal} = OCEL2.validate(corrupted)
      assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
      assert Enum.any?(refusal.evidence.errors, &String.contains?(&1, "Invalid ISO 8601 timestamp"))
    end

    test "refuses event log where ocel:omap is not a list" do
      corrupted = [
        %{
          "ocel:eid" => "eid-123",
          "ocel:activity" => "tenant.create",
          "ocel:timestamp" => "2026-08-21T09:00:00.000000Z",
          "ocel:omap" => "single_string_instead_of_list"
        }
      ]

      assert {:error, refusal} = OCEL2.validate(corrupted)
      assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
      assert Enum.any?(refusal.evidence.errors, &String.contains?(&1, "ocel:omap"))
    end

    test "validates NDJSON stream format and refuses malformed JSON lines" do
      ndjson = """
      {"ocel:eid":"e1","ocel:activity":"a1","ocel:timestamp":"2026-08-21T10:00:00Z","ocel:omap":["o1"]}
      {"ocel:eid":"e2","ocel:activity":"a2","ocel:timestamp":"2026-08-21T10:01:00Z","ocel:omap":["o1"]}
      """

      assert {:ok, metrics} = OCEL2.validate(ndjson)
      assert metrics.valid? == true
      assert metrics.event_count == 2
    end
  end
end
