defmodule AshR2RML.VKG.Batch do
  @moduledoc """
  Runs independent VKG requests without letting one refusal erase other evidence.
  """

  alias AshR2RML.VKG

  @spec run([map()], keyword()) :: %{admitted: [map()], refused: [map()]}
  def run(requests, common_opts \\ []) when is_list(requests) do
    requests
    |> Enum.with_index()
    |> Enum.reduce(%{admitted: [], refused: []}, fn {request, index}, acc ->
      contracts = Map.get(request, :contracts, Map.get(request, "contracts", []))
      request_opts = Map.get(request, :opts, Map.get(request, "opts", []))
      opts = Keyword.merge(common_opts, List.wrap(request_opts))

      case VKG.query(contracts, opts) do
        {:ok, session} ->
          admitted = %{index: index, contracts: contracts, session: session}
          %{acc | admitted: [admitted | acc.admitted]}

        {:error, reason} ->
          refused = %{index: index, contracts: contracts, reason: reason}
          %{acc | refused: [refused | acc.refused]}
      end
    end)
    |> then(fn result ->
      %{
        admitted: Enum.reverse(result.admitted),
        refused: Enum.reverse(result.refused)
      }
    end)
  end
end
