# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenRuntime.Eventing do
  @moduledoc "Event-envelope admission with causation, correlation, OCEL, and receipt identity."

  @spec admit(map()) :: {:ok, map()} | {:error, atom()}
  def admit(%{event_id: event_id, correlation_id: correlation_id, receipt_id: receipt_id} = event)
      when is_binary(event_id) and byte_size(event_id) > 0 and is_binary(correlation_id) and
             byte_size(correlation_id) > 0 and is_binary(receipt_id) and byte_size(receipt_id) > 0 do
    envelope =
      event
      |> Map.put_new(:canonical_evidence, "ggen/ecosystem/ocel/current")
      |> Map.put_new(:causation_id, nil)

    {:ok, envelope}
  end

  def admit(_), do: {:error, :REFUSED_RUNTIME_EVENT_ENVELOPE_INCOMPLETE}
end
