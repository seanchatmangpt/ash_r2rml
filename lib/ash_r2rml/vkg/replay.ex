defmodule AshR2RML.VKG.Replay do
  @moduledoc """
  Deterministic replay court for VKG observations and receipts.

  `reconstruct/2` is the inverse of `AshR2RML.VKG.Executor.execute/2`: it feeds
  the recorded observations back through the very same executor (provenance,
  merge and row bound included) via a recorded-observation engine, so no merge
  or provenance logic is duplicated here.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Executor, QueryPlan, Receipt, Result}

  defmodule RecordedEngine do
    @moduledoc false
    # Engine that returns previously recorded observations instead of executing.
    def execute(stage, opts) do
      case opts |> Keyword.fetch!(:recorded_observations) |> Map.fetch(stage.contract_id) do
        {:ok, observation} ->
          {:ok, observation}

        :error ->
          {:error,
           %{
             refusal:
               Refusal.new(
                 :REFUSED_VKG_REPLAY,
                 stage.contract_id,
                 "no recorded observation for stage",
                 %{}
               )
           }}
      end
    end
  end

  @spec verify(Receipt.t(), QueryPlan.t(), Result.t(), map() | nil) :: :ok | {:error, Refusal.t()}
  def verify(%Receipt{} = receipt, %QueryPlan{} = plan, %Result{} = result, observations \\ nil) do
    Receipt.verify(receipt, plan, result, observations)
  end

  @doc """
  Rebuilds the sealed result from recorded observations (`%{contract_id => observation}`).

  Refuses observation sets that omit a planned contract or carry an unplanned
  one, and any execution refusal (bounds, malformed observations).
  """
  @spec reconstruct(QueryPlan.t(), %{optional(String.t()) => map()}) ::
          {:ok, Result.t()} | {:error, Refusal.t()}
  def reconstruct(%QueryPlan{} = plan, observations) when is_map(observations) do
    planned = MapSet.new(plan.contract_ids)
    recorded = observations |> Map.keys() |> MapSet.new()

    cond do
      not MapSet.equal?(planned, recorded) ->
        refuse(:contract_ids, "recorded observations must match the planned contracts exactly", %{
          missing: planned |> MapSet.difference(recorded) |> Enum.sort(),
          extra: recorded |> MapSet.difference(planned) |> Enum.sort()
        })

      not Enum.all?(observations, fn {_id, obs} -> is_map(obs) and is_list(Map.get(obs, :rows)) end) ->
        refuse(:observations, "recorded observations must carry a rows list", %{})

      true ->
        case Executor.replay(plan, RecordedEngine, recorded_observations: observations) do
          {:ok, result, _observations} ->
            {:ok, result}

          {:error, %Refusal{code: :REFUSED_VKG_REPLAY} = refusal} ->
            {:error, refusal}

          {:error, %Refusal{} = cause} ->
            refuse(:reconstruct, "recorded observations do not reconstruct a result", %{cause: cause})
        end
    end
  end

  def reconstruct(%QueryPlan{}, other),
    do: refuse(:observations, "recorded observations must be a map", %{got: inspect(other)})

  @spec compare(Receipt.t(), Result.t()) :: {:ok, map()} | {:error, Refusal.t()}
  def compare(%Receipt{} = receipt, %Result{} = result) do
    if receipt.result_sha256 == result.sha256 and receipt.row_count === result.row_count and
         receipt.standing === result.standing do
      {:ok,
       %{
         receipt_id: receipt.id,
         result_sha256: result.sha256,
         row_count: result.row_count,
         deterministic?: true
       }}
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_REPLAY,
         receipt.id,
         "reconstructed VKG result differs from the sealed receipt",
         %{
           expected_sha256: receipt.result_sha256,
           observed_sha256: result.sha256,
           expected_rows: receipt.row_count,
           observed_rows: result.row_count
         }
       )}
    end
  end

  defp refuse(subject, detail, evidence),
    do: {:error, Refusal.new(:REFUSED_VKG_REPLAY, subject, detail, evidence)}
end
