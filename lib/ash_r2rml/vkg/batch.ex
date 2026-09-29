defmodule AshR2RML.VKG.Batch do
  @moduledoc """
  Runs independent VKG requests without letting one refusal erase other evidence.

  Every malformed input is a typed refusal in the `:refused` list, never a raise:
  a non-list request list, non-keyword common options, an invalid `:max_requests`,
  a request that is not a map, non-list `:contracts` and non-keyword `:opts`.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG

  @default_max_requests 1_000

  @type outcome :: %{admitted: [map()], refused: [map()]}

  @spec run(term(), keyword()) :: outcome()
  def run(requests, common_opts \\ [])

  def run(requests, common_opts) when is_list(requests) and is_list(common_opts) do
    with true <- Keyword.keyword?(common_opts) || bad_options(common_opts),
         max = Keyword.get(common_opts, :max_requests, @default_max_requests),
         true <- (is_integer(max) and max > 0) || bad_max(max) do
      common_opts = Keyword.delete(common_opts, :max_requests)

      if length(requests) > max do
        bound =
          Refusal.new(:REFUSED_RESOURCE_BOUND, :vkg_batch, "batch exceeds the request bound", %{
            observed: length(requests),
            limit: max
          })

        whole(bound)
      else
        do_run(requests, common_opts)
      end
    else
      %{refused: _} = refused -> refused
    end
  end

  def run(requests, common_opts) when is_list(common_opts) do
    whole(
      Refusal.new(:REFUSED_VKG_QUERY_SCOPE, :vkg_batch, "batch requests must be a list", %{
        got: inspect(requests, limit: 5)
      })
    )
  end

  def run(_requests, common_opts), do: bad_options(common_opts)

  defp bad_options(common_opts) do
    whole(
      Refusal.new(:REFUSED_VKG_QUERY_PLAN, :options, "batch options must be a keyword list", %{
        got: inspect(common_opts, limit: 5)
      })
    )
  end

  defp bad_max(max) do
    whole(
      Refusal.new(:REFUSED_VKG_QUERY_PLAN, :max_requests, "batch :max_requests must be a positive integer", %{
        got: inspect(max)
      })
    )
  end

  defp whole(refusal), do: %{admitted: [], refused: [%{index: nil, contracts: [], reason: refusal}]}

  defp do_run(requests, common_opts) do
    requests
    |> Enum.with_index()
    |> Enum.reduce(%{admitted: [], refused: []}, fn {request, index}, acc ->
      case run_request(request, common_opts) do
        {:ok, contracts, session} ->
          %{acc | admitted: [%{index: index, contracts: contracts, session: session} | acc.admitted]}

        {:error, contracts, reason} ->
          %{acc | refused: [%{index: index, contracts: contracts, reason: reason} | acc.refused]}
      end
    end)
    |> then(fn result ->
      %{admitted: Enum.reverse(result.admitted), refused: Enum.reverse(result.refused)}
    end)
  end

  defp run_request(request, _common_opts) when not is_map(request) or is_struct(request) do
    {:error, [],
     Refusal.new(:REFUSED_VKG_QUERY_SCOPE, :vkg_batch, "batch request must be a map", %{
       request: inspect(request, limit: 5)
     })}
  end

  defp run_request(request, common_opts) do
    contracts = Map.get(request, :contracts, Map.get(request, "contracts", []))
    request_opts = Map.get(request, :opts, Map.get(request, "opts", []))

    cond do
      not is_list(contracts) ->
        {:error, [],
         Refusal.new(:REFUSED_VKG_QUERY_SCOPE, :contracts, "VKG contract ids must be a list", %{
           got: inspect(contracts, limit: 5)
         })}

      not (is_nil(request_opts) or (is_list(request_opts) and Keyword.keyword?(request_opts))) ->
        {:error, contracts,
         Refusal.new(:REFUSED_VKG_QUERY_PLAN, :options, "batch request :opts must be a keyword list", %{
           got: inspect(request_opts, limit: 5)
         })}

      true ->
        query(contracts, Keyword.merge(common_opts, request_opts || []))
    end
  end

  defp query(contracts, opts) do
    case VKG.query(contracts, opts) do
      {:ok, session} -> {:ok, contracts, session}
      {:error, reason} -> {:error, contracts, reason}
    end
  rescue
    error ->
      {:error, contracts,
       Refusal.new(:REFUSED_VKG_EXECUTION, :vkg_batch, "VKG batch request raised", %{
         error: Exception.message(error)
       })}
  end
end
