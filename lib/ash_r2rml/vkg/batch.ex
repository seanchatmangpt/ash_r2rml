defmodule AshR2RML.VKG.Batch do
  @moduledoc "Runs independent VKG requests without letting one refusal erase other evidence."
  alias AshR2RML.VKG
  def run(requests, common_opts \\ []) when is_list(requests) do
    requests |> Enum.with_index() |> Enum.reduce(%{admitted: [], refused: []}, fn {request,index},acc ->
      contracts=Map.get(request,:contracts,Map.get(request,"contracts",[]))
      request_opts=Map.get(request,:opts,Map.get(request,"opts",[]))
      opts=Keyword.merge(common_opts,List.wrap(request_opts))
      case VKG.query(contracts,opts) do
        {:ok,session}->%{acc|admitted:[%{index:index,contracts:contracts,session:session}|acc.admitted]}
        {:error,reason}->%{acc|refused:[%{index:index,contracts:contracts,reason:reason}|acc.refused]}
      end
    end) |> then(fn r->%{admitted:Enum.reverse(r.admitted),refused:Enum.reverse(r.refused)} end)
  end
end
