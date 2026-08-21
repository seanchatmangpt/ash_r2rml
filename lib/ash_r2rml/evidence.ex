# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Evidence do
  @moduledoc """
  Stable content identities for evidence already owned by AshR2RML.

  This module does not create a second receipt hierarchy. It gives existing
  mapping bundles, SPARQL observations, OBDA observations, compiler receipts,
  and ordinary results a common content-addressed identity so Reactor/OCEL can
  correlate the exact artifacts that actually flowed through a run.

  Volatile execution details (wall-clock timestamps, random OCEL event IDs,
  durations, Reactor run UUIDs, and raw external stdout) are deliberately
  outside semantic evidence identity. Query, mapping, normalized result,
  strategy, endpoint, and evidence-kind boundaries remain inside it.
  """

  alias AshR2RML.OBDA.Observation, as: OBDAObservation
  alias AshR2RML.SPARQL.Observation, as: SPARQLObservation
  alias AshR2RML.SPARQL.Result

  @spec id(term()) :: String.t()
  def id(%SPARQLObservation{} = observation) do
    sha256(%{
      kind: :sparql_observation,
      strategy: observation.strategy,
      query_sha256: observation.query_sha256,
      query_form: observation.query_form,
      result_sha256: observation.result_sha256 || Result.hash_rows(observation.rows),
      result_kind: observation.result_kind,
      standing: observation.standing,
      evidence_kind: observation.evidence_kind,
      endpoint: observation.endpoint,
      mapping_sha256: get(observation.metadata, :mapping_sha256),
      engine: get(observation.metadata, :engine) || get(observation.metadata, :client)
    })
  end

  def id(%OBDAObservation{} = observation) do
    sha256(%{
      kind: :obda_observation,
      system: observation.system,
      evidence_kind: observation.evidence_kind,
      exit_status: observation.exit_status,
      command_sha256: observation.command_sha256,
      query_sha256: observation.query_sha256,
      mapping_sha256: observation.mapping_sha256,
      result_sha256: Result.hash_rows(observation.rows),
      standing: observation.standing
    })
  end

  def id(%AshR2RML.CompilationReceipt{} = receipt), do: sha256(Map.from_struct(receipt))
  def id(%AshR2RML.Mapping.Bundle{} = bundle), do: sha256(AshR2RML.Mapping.normalize(bundle))
  def id(value), do: sha256(value)

  @doc """
  Returns a deterministic digest of one correlated OCEL execution trace.

  `execution_id` selects the run. Once selected, the run UUID itself and other
  transport-time values are normalized away, so two independent Reactor runs
  with the same semantic activities/results produce the same trace identity.
  """
  @spec ocel_trace_id([map()], String.t()) :: {:ok, String.t()} | {:error, AshR2RML.Refusal.t()}
  def ocel_trace_id(events, execution_id) when is_list(events) and is_binary(execution_id) do
    selected =
      events
      |> Enum.filter(&(get_in(&1, ["ocel:vmap", "execution_id"]) == execution_id))
      |> Enum.map(&canonical_ocel_event/1)
      |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))

    case selected do
      [] ->
        {:error,
         AshR2RML.Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           execution_id,
           "OCEL log contains no events for the requested Reactor execution",
           %{execution_id: execution_id}
         )}

      _ ->
        {:ok, sha256(selected)}
    end
  end

  @doc "Extract the Reactor execution id propagated through middleware context."
  @spec execution_id(term()) :: String.t() | nil
  def execution_id(context) when is_map(context) do
    Map.get(context, :ash_r2rml_execution_id) ||
      Map.get(context, "ash_r2rml_execution_id") ||
      Map.get(context, :execution_id) ||
      Map.get(context, "execution_id")
  end

  def execution_id(_), do: nil

  @spec sha256(term()) :: String.t()
  def sha256(value) when is_binary(value) do
    :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  end

  def sha256(value) do
    value
    |> canonical()
    |> :erlang.term_to_binary([:deterministic])
    |> sha256()
  end

  defp canonical_ocel_event(event) do
    vmap =
      event
      |> Map.get("ocel:vmap", %{})
      |> Map.drop(["duration_ms", "started_at", "completed_at", "execution_id"])

    %{
      activity: Map.get(event, "ocel:activity"),
      lifecycle: Map.get(event, "ocel:lifecycle"),
      omap: event |> Map.get("ocel:omap", []) |> Enum.map(&normalize_run_object/1) |> Enum.sort(),
      e2o:
        event
        |> Map.get("ocel:e2o", [])
        |> Enum.map(&normalize_e2o/1)
        |> Enum.map(&canonical/1)
        |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic])),
      vmap: canonical(vmap)
    }
  end

  defp normalize_e2o(%{"ocel:oid" => oid} = relation),
    do: Map.put(relation, "ocel:oid", normalize_run_object(oid))

  defp normalize_e2o(relation), do: relation

  defp normalize_run_object("reactor-run:" <> _), do: "reactor-run:*"
  defp normalize_run_object(other), do: other

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {canonical(key), canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key, [:deterministic]) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(other), do: other

  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp get(_, _), do: nil
end
