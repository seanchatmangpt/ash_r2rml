defmodule AshR2RML.VKG.Batch do
  @moduledoc """
  Runs independent VKG requests without letting one refusal erase other evidence.
  """

  alias AshR2RML.VKG

  @spec run([map()], keyword()) :: %{admitted: [map()], refused: [map()]}
  @default_max_requests 1_000

  def run(requests, common_opts \\ []) when is_list(requests) do
    max = Keyword.get(common_opts, :max_requests, @default_max_requests)
    common_opts = Keyword.delete(common_opts, :max_requests)

    if length(requests) > max do
      bound =
        AshR2RML.Refusal.new(:REFUSED_RESOURCE_BOUND, :vkg_batch, "batch exceeds the request bound", %{
          observed: length(requests),
          limit: max
        })

      %{admitted: [], refused: [%{index: nil, contracts: [], reason: bound}]}
    else
      do_run(requests, common_opts)
    end
  end

  defp do_run(requests, common_opts) do
    requests
    |> Enum.with_index()
    |> Enum.reduce(%{admitted: [], refused: []}, fn
      {request, index}, acc when not is_map(request) ->
        refusal =
          AshR2RML.Refusal.new(:REFUSED_VKG_QUERY_SCOPE, :vkg_batch, "batch request must be a map", %{
            request: inspect(request, limit: 5)
          })

        %{acc | refused: [%{index: index, contracts: [], reason: refusal} | acc.refused]}

      {request, index}, acc ->
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
