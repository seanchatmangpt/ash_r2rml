defmodule AshR2RML.VKG.Replay do
  @moduledoc """
  Deterministic replay court for VKG observations and receipts.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{QueryPlan, Receipt, Result}

  @spec verify(Receipt.t(), QueryPlan.t(), Result.t()) :: :ok | {:error, Refusal.t()}
  def verify(%Receipt{} = receipt, %QueryPlan{} = plan, %Result{} = result) do
    Receipt.verify(receipt, plan, result)
  end

  @spec reconstruct(QueryPlan.t(), %{optional(String.t()) => [map()]}) :: Result.t()
  def reconstruct(%QueryPlan{} = plan, rows_by_contract) when is_map(rows_by_contract) do
    ordered_rows =
      Enum.flat_map(plan.contract_ids, fn id ->
        Map.get(rows_by_contract, id, [])
      end)

    Result.build(plan.sha256, ordered_rows)
  end

  @spec compare(Receipt.t(), Result.t()) :: {:ok, map()} | {:error, Refusal.t()}
  def compare(%Receipt{} = receipt, %Result{} = result) do
    if receipt.result_sha256 == result.sha256 and receipt.row_count == result.row_count do
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
end
