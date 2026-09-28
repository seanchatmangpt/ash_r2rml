defmodule AshR2RML.VKG.Receipt do
  @moduledoc """
  Deterministic replay identity for one admitted VKG plan and observed result.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{QueryPlan, Result}

  @enforce_keys [
    :id,
    :plan_sha256,
    :catalog_sha256,
    :contract_ids,
    :observation_sha256_by_contract,
    :result_sha256,
    :row_count
  ]

  defstruct [
    :id,
    :plan_sha256,
    :catalog_sha256,
    :contract_ids,
    :observation_sha256_by_contract,
    :result_sha256,
    :row_count,
    :previous,
    authority: :NONE,
    standing: :observed_not_actuated
  ]

  @type t :: %__MODULE__{}

  @spec build(QueryPlan.t(), Result.t(), map(), String.t() | nil) :: t()
  def build(%QueryPlan{} = plan, %Result{} = result, observations, previous \\ nil) do
    observation_sha256_by_contract =
      observations
      |> Enum.map(fn {id, observation} ->
        {id, Map.get(observation, :observation_sha256)}
      end)
      |> Enum.sort()
      |> Map.new()

    payload =
      {plan.sha256, plan.catalog_sha256, plan.contract_ids, observation_sha256_by_contract, result.sha256,
       result.row_count, previous}

    sha256 = hash(payload)

    %__MODULE__{
      id: "vkg-receipt-" <> binary_part(sha256, 0, 20),
      plan_sha256: plan.sha256,
      catalog_sha256: plan.catalog_sha256,
      contract_ids: plan.contract_ids,
      observation_sha256_by_contract: observation_sha256_by_contract,
      result_sha256: result.sha256,
      row_count: result.row_count,
      previous: previous,
      authority: :NONE,
      standing: :observed_not_actuated
    }
  end

  @spec verify(t(), QueryPlan.t(), Result.t()) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{} = receipt, %QueryPlan{} = plan, %Result{} = result) do
    cond do
      receipt.authority != :NONE ->
        refusal(:authority, "VKG receipt cannot acquire actuation authority", %{
          authority: receipt.authority
        })

      receipt.plan_sha256 != plan.sha256 ->
        refusal(:plan, "VKG receipt references a different plan", %{
          receipt: receipt.plan_sha256,
          plan: plan.sha256
        })

      receipt.catalog_sha256 != plan.catalog_sha256 ->
        refusal(:catalog, "VKG receipt references a different catalog", %{
          receipt: receipt.catalog_sha256,
          plan: plan.catalog_sha256
        })

      receipt.result_sha256 != result.sha256 ->
        refusal(:result, "VKG result digest does not replay", %{
          receipt: receipt.result_sha256,
          result: result.sha256
        })

      receipt.row_count != result.row_count ->
        refusal(:row_count, "VKG result row count does not replay", %{
          receipt: receipt.row_count,
          result: result.row_count
        })

      true ->
        :ok
    end
  end

  @spec chain_valid?([t()]) :: boolean()
  def chain_valid?([]), do: true

  def chain_valid?([first | rest]) do
    Enum.reduce_while(rest, first.id, fn receipt, previous_id ->
      if receipt.previous == previous_id do
        {:cont, receipt.id}
      else
        {:halt, false}
      end
    end) != false
  end

  defp hash(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_REPLAY, subject, detail, evidence)}
  end
end
