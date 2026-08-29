# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.EventingTest do
  use ExUnit.Case, async: true

  alias AshR2RML.GgenRuntime.Eventing

  test "admits receipted event envelope" do
    assert {:ok, event} =
             Eventing.admit(%{event_id: "e1", correlation_id: "c1", receipt_id: "r1"})

    assert event.canonical_evidence == "ggen/ecosystem/ocel/current"
    assert Map.has_key?(event, :causation_id)
  end

  test "refuses unreceipted event envelopes" do
    assert {:error, :REFUSED_RUNTIME_EVENT_ENVELOPE_INCOMPLETE} =
             Eventing.admit(%{event_id: "e1", correlation_id: "c1"})
  end
end
