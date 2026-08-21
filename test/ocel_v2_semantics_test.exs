# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Telemetry.OCEL2SemanticsTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Telemetry.OCEL2
  alias AshR2RML.Telemetry.OCEL2.{Event, Log, Object, Relationship}

  defp event(id, activity, timestamp, objects, extra \\ %{}) do
    Map.merge(
      %{
        "ocel:eid" => id,
        "ocel:activity" => activity,
        "ocel:timestamp" => timestamp,
        "ocel:omap" => objects,
        "ocel:vmap" => %{}
      },
      extra
    )
  end

  test "invalid NDJSON is refused instead of silently disappearing" do
    raw = Jason.encode!(event("e1", "created", "2026-08-21T20:00:00Z", ["order:1"])) <> "\n{not-json}\n"

    assert {:error, refusal} = OCEL2.validate(raw)
    assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
    assert refusal.evidence.line == 2
  end

  test "duplicate event identities are refused" do
    events = [
      event("same", "created", "2026-08-21T20:00:00Z", ["order:1"]),
      event("same", "paid", "2026-08-21T20:01:00Z", ["order:1"])
    ]

    assert {:error, refusal} = OCEL2.validate(events)
    assert refusal.code == :REFUSED_INVALID_OCEL2_LOG
    assert Enum.any?(refusal.evidence.errors, &String.contains?(&1, "duplicate ocel:eid"))
  end

  test "qualified E2O and compatibility OMAP must denote the same objects" do
    events = [
      event("e1", "approved", "2026-08-21T20:00:00Z", ["order:1"], %{
        "ocel:e2o" => [%{"ocel:oid" => "actor:7", "ocel:qualifier" => "approver"}]
      })
    ]

    assert {:error, refusal} = OCEL2.validate(events)
    assert Enum.any?(refusal.evidence.errors, &String.contains?(&1, "disagree"))
  end

  test "bounded log validates qualified E2O and O2O against the object catalog" do
    log = %Log{
      objects: %{
        "order:1" => %Object{id: "order:1", type: "Order"},
        "customer:1" => %Object{id: "customer:1", type: "Customer"}
      },
      events: [
        %Event{
          id: "e1",
          activity: "order.created",
          timestamp: "2026-08-21T20:00:00Z",
          omap: ["order:1", "customer:1"],
          e2o: [
            {"order:1", "created"},
            {"customer:1", "placed_by"}
          ]
        }
      ],
      o2o: [
        %Relationship{source_id: "order:1", target_id: "customer:1", qualifier: "customer"}
      ]
    }

    assert {:ok, metrics} = OCEL2.validate(log)
    assert metrics.object_catalog_valid?
    assert metrics.conformance_evaluated? == false
    assert metrics.conformance_score == nil
  end

  test "event value maps are observations, not ambient object-state mutations" do
    events = [
      event("e1", "order.observed", "2026-08-21T20:00:00Z", ["order:1"], %{
        "ocel:vmap" => %{"status" => "paid"}
      })
    ]

    assert {:ok, replay} = OCEL2.reconstruct_from_events(events)
    assert replay.objects["order:1"].attributes == %{}
    assert [{"order.observed", _, %{"status" => "paid"}}] = replay.objects["order:1"].history
  end

  test "independent same-timestamp writes commute without inventing causal order" do
    timestamp = "2026-08-21T20:00:00Z"

    events = [
      event("b", "order.total", timestamp, ["order:1"], %{
        "ocel:objectChanges" => %{"order:1" => %{"total" => 42}}
      }),
      event("a", "order.status", timestamp, ["order:1"], %{
        "ocel:objectChanges" => %{"order:1" => %{"status" => "paid"}}
      })
    ]

    assert {:ok, replay} = OCEL2.reconstruct_from_events(events)
    assert replay.objects["order:1"].attributes == %{"status" => "paid", "total" => 42}
    assert replay.total_order_inferred? == false
    assert [%{event_ids: ["a", "b"]}] = replay.concurrency_layers
  end

  test "conflicting same-timestamp writes are a typed ambiguity" do
    timestamp = "2026-08-21T20:00:00Z"

    events = [
      event("a", "order.open", timestamp, ["order:1"], %{
        "ocel:objectChanges" => %{"order:1" => %{"status" => "open"}}
      }),
      event("b", "order.cancel", timestamp, ["order:1"], %{
        "ocel:objectChanges" => %{"order:1" => %{"status" => "cancelled"}}
      })
    ]

    assert {:error, refusal} = OCEL2.reconstruct_from_events(events)
    assert refusal.code == :REFUSED_AMBIGUOUS_EVENT_ORDER
    assert refusal.evidence.timestamp == timestamp
  end
end
