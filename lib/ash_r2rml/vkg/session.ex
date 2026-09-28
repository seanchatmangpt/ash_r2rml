defmodule AshR2RML.VKG.Session do
  @moduledoc """
  Immutable VKG catalog, plan, result, observation, and receipt session.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Catalog, QueryPlan, Receipt, Replay, Result}

  @enforce_keys [:catalog_sha256, :plan, :result, :observations, :receipt]
  defstruct [:catalog_sha256, :plan, :result, :observations, :receipt]

  @type t :: %__MODULE__{}

  @spec new(Catalog.t(), QueryPlan.t(), Result.t(), map(), Receipt.t()) :: t()
  def new(
        %Catalog{} = catalog,
        %QueryPlan{} = plan,
        %Result{} = result,
        observations,
        %Receipt{} = receipt
      ) do
    %__MODULE__{
      catalog_sha256: catalog.sha256,
      plan: plan,
      result: result,
      observations: observations,
      receipt: receipt
    }
  end

  @spec verify(t()) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{} = session) do
    if session.catalog_sha256 == session.plan.catalog_sha256 do
      Replay.verify(session.receipt, session.plan, session.result)
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_REPLAY,
         :catalog,
         "session catalog differs from plan catalog",
         %{session: session.catalog_sha256, plan: session.plan.catalog_sha256}
       )}
    end
  end

  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = session) do
    %{
      catalog_sha256: session.catalog_sha256,
      plan_id: session.plan.id,
      plan_sha256: session.plan.sha256,
      contracts: session.plan.contract_ids,
      result_sha256: session.result.sha256,
      row_count: session.result.row_count,
      receipt_id: session.receipt.id,
      standing: session.result.standing
    }
  end
end
