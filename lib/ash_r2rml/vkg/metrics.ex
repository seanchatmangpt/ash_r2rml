defmodule AshR2RML.VKG.Metrics do
  @moduledoc """
  Pure metrics projection over a completed VKG session.
  """

  alias AshR2RML.VKG.Session

  @spec from_session(Session.t()) :: map()
  def from_session(%Session{} = session) do
    observations = Map.values(session.observations)

    durations =
      observations
      |> Enum.map(&Map.get(&1, :duration_ms))
      |> Enum.filter(&is_integer/1)

    bytes =
      observations
      |> Enum.map(&Map.get(&1, :output_bytes))
      |> Enum.filter(&is_integer/1)

    %{
      contract_count: length(session.plan.contract_ids),
      observed_contract_count: map_size(session.observations),
      row_count: session.result.row_count,
      source_row_counts: session.result.sources,
      total_output_bytes: Enum.sum(bytes),
      total_duration_ms: Enum.sum(durations),
      max_stage_duration_ms: Enum.max(durations, fn -> 0 end),
      plan_sha256: session.plan.sha256,
      result_sha256: session.result.sha256,
      replay_verifiable?: Session.verify(session) == :ok
    }
  end
end
