defmodule AshR2RML.VKG.Receipt do
  @moduledoc """
  Deterministic replay identity for one admitted VKG plan and observed result.

  The receipt digest (`sha256`, full length) covers every field including
  `previous`, `authority` and `standing`; `id` is its 20 hex character prefix.
  `verify/3,4` recomputes plan integrity, result integrity and the receipt
  digest itself, so no stored digest is trusted.

  `previous` accepts a `%Receipt{}` or a receipt id string and is normalized to
  the id. Chains must start at `previous == nil` unless an explicit `:anchor`
  id is given to `chain_valid?/2`.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{QueryPlan, Result, Serializer}

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
    :sha256,
    :plan_sha256,
    :catalog_sha256,
    :contract_ids,
    :observation_sha256_by_contract,
    :result_sha256,
    :row_count,
    :previous,
    evidence_sha256_by_contract: %{},
    authority: :NONE,
    standing: :observed_not_actuated
  ]

  @type t :: %__MODULE__{}

  @id_prefix "vkg-receipt-"
  @id_pattern ~r/\A#{@id_prefix}[0-9a-f]{20}\z/

  @spec build(QueryPlan.t(), Result.t(), map(), t() | String.t() | nil) :: t()
  def build(%QueryPlan{} = plan, %Result{} = result, observations, previous \\ nil) do
    observation_sha256_by_contract =
      observations
      |> Enum.map(fn {id, observation} ->
        {id, Map.get(observation, :observation_sha256)}
      end)
      |> Enum.sort()
      |> Map.new()

    receipt = %__MODULE__{
      id: "",
      plan_sha256: plan.sha256,
      catalog_sha256: plan.catalog_sha256,
      contract_ids: plan.contract_ids,
      observation_sha256_by_contract: observation_sha256_by_contract,
      evidence_sha256_by_contract: evidence_digests(observations),
      result_sha256: result.sha256,
      row_count: result.row_count,
      previous: normalize_previous(previous),
      authority: :NONE,
      standing: result.standing
    }

    sha256 = compute_sha256(receipt)
    %{receipt | sha256: sha256, id: @id_prefix <> binary_part(sha256, 0, 20)}
  end

  @evidence_fields ~w(status standing system system_version evidence_kind exit_status command_sha256
                      query_sha256 mapping_sha256 session_sha256 output_sha256 output_bytes row_count
                      duration_ms bounded? observation_sha256)a

  @doc """
  Digest over every identity-relevant observation field (evidence kind, standing,
  system, output digest, duration, ...), keyed by contract id. `verify/4`
  recomputes it from the supplied observations.
  """
  @spec evidence_digests(map()) :: %{optional(String.t()) => String.t()}
  def evidence_digests(observations) when is_map(observations) do
    Map.new(observations, fn {id, observation} ->
      fields = Map.new(@evidence_fields, fn field -> {Atom.to_string(field), Map.get(observation, field)} end)
      {id, Serializer.digest(%{"kind" => "vkg.observation_evidence", "contract_id" => id, "fields" => fields})}
    end)
  end

  @doc "Full sha256 recomputed from the receipt payload (never the stored one)."
  @spec compute_sha256(t()) :: String.t()
  def compute_sha256(%__MODULE__{} = receipt) do
    Serializer.digest(%{
      "kind" => "vkg.receipt",
      "plan_sha256" => receipt.plan_sha256,
      "catalog_sha256" => receipt.catalog_sha256,
      "contract_ids" => receipt.contract_ids,
      "observation_sha256_by_contract" => receipt.observation_sha256_by_contract,
      "evidence_sha256_by_contract" => receipt.evidence_sha256_by_contract,
      "result_sha256" => receipt.result_sha256,
      "row_count" => receipt.row_count,
      "previous" => receipt.previous,
      "authority" => receipt.authority,
      "standing" => receipt.standing
    })
  end

  @doc """
  Verifies the receipt alone: authority, previous-id shape, and that `sha256`
  and `id` equal the digest recomputed from the payload.
  """
  @spec verify_integrity(t()) :: :ok | {:error, Refusal.t()}
  def verify_integrity(%__MODULE__{} = receipt) do
    recomputed = compute_sha256(receipt)

    cond do
      receipt.authority != :NONE ->
        refusal(:authority, "VKG receipt cannot acquire actuation authority", %{
          authority: receipt.authority
        })

      not (is_nil(receipt.previous) or valid_id?(receipt.previous)) ->
        refusal(:previous, "VKG receipt previous must be nil or a receipt id", %{
          previous: inspect(receipt.previous)
        })

      receipt.sha256 != recomputed ->
        refusal(:sha256, "VKG receipt digest does not match its payload", %{
          receipt: receipt.sha256,
          recomputed: recomputed
        })

      receipt.id != @id_prefix <> binary_part(recomputed, 0, 20) ->
        refusal(:id, "VKG receipt id does not match its payload digest", %{
          receipt: receipt.id,
          recomputed: @id_prefix <> binary_part(recomputed, 0, 20)
        })

      true ->
        :ok
    end
  end

  @spec verify(t(), QueryPlan.t(), Result.t(), map() | nil) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{} = receipt, %QueryPlan{} = plan, %Result{} = result, observations \\ nil) do
    with :ok <- authority(receipt),
         :ok <- plan_integrity(plan),
         :ok <- bind_plan(receipt, plan),
         :ok <- bind_result(receipt, plan, result),
         :ok <- verify_integrity(receipt),
         :ok <- bind_standing(receipt, result) do
      verify_observations(receipt, observations)
    end
  end

  defp authority(%{authority: :NONE}), do: :ok

  defp authority(receipt) do
    refusal(:authority, "VKG receipt cannot acquire actuation authority", %{
      authority: receipt.authority
    })
  end

  defp plan_integrity(plan) do
    case QueryPlan.verify(plan) do
      :ok ->
        :ok

      {:error, %Refusal{} = cause} ->
        refusal(:plan, "VKG plan integrity does not verify", %{cause: cause})
    end
  end

  defp bind_plan(receipt, plan) do
    cond do
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

      receipt.contract_ids != plan.contract_ids ->
        refusal(:contract_ids, "VKG receipt contract ids differ from the plan", %{
          receipt: receipt.contract_ids,
          plan: plan.contract_ids
        })

      true ->
        :ok
    end
  end

  defp bind_result(receipt, plan, result) do
    cond do
      result.plan_sha256 != plan.sha256 ->
        refusal(:result_plan, "VKG result was built for a different plan", %{
          result: result.plan_sha256,
          plan: plan.sha256
        })

      (result_error = result_error(result)) != nil ->
        refusal(:result, "VKG result does not verify against its rows", %{cause: result_error})

      receipt.result_sha256 != result.sha256 ->
        refusal(:result, "VKG result digest does not replay", %{
          receipt: receipt.result_sha256,
          result: result.sha256
        })

      receipt.row_count !== result.row_count ->
        refusal(:row_count, "VKG result row count does not replay", %{
          receipt: receipt.row_count,
          result: result.row_count
        })

      true ->
        :ok
    end
  end

  defp bind_standing(receipt, result) do
    if receipt.standing === result.standing do
      :ok
    else
      refusal(:standing, "VKG receipt standing does not match the sealed result standing", %{
        receipt: receipt.standing,
        result: result.standing
      })
    end
  end

  defp result_error(result) do
    case Result.verify(result) do
      :ok -> nil
      {:error, cause} -> cause
    end
  end

  defp verify_observations(_receipt, nil), do: :ok

  defp verify_observations(receipt, observations) when is_map(observations) do
    observed =
      observations
      |> Enum.map(fn {id, observation} -> {id, Map.get(observation, :observation_sha256)} end)
      |> Enum.sort()
      |> Map.new()

    cond do
      observed != receipt.observation_sha256_by_contract ->
        refusal(:observations, "VKG observation digests do not match the receipt", %{
          receipt: receipt.observation_sha256_by_contract,
          observed: observed
        })

      evidence_digests(observations) != receipt.evidence_sha256_by_contract ->
        refusal(
          :observations,
          "VKG observation evidence (kind, standing, system, output) does not match the receipt",
          %{
            receipt: receipt.evidence_sha256_by_contract,
            observed: evidence_digests(observations)
          }
        )

      true ->
        :ok
    end
  end

  defp verify_observations(_receipt, other),
    do: refusal(:observations, "VKG observations must be a map", %{got: inspect(other)})

  @doc """
  Verifies a receipt chain. Every receipt must verify its own digest and id,
  the head must have `previous == nil` (or equal the `:anchor` id option), and
  each later receipt must point at its predecessor's id.
  """
  @spec chain_valid?([t()], keyword()) :: boolean()
  def chain_valid?(chain, opts \\ [])
  def chain_valid?([], _opts), do: true

  def chain_valid?([%__MODULE__{} = first | rest] = chain, opts) do
    anchor = Keyword.get(opts, :anchor)

    Enum.all?(chain, fn
      %__MODULE__{} = receipt -> verify_integrity(receipt) == :ok
      _ -> false
    end) and
      first.previous == anchor and
      links?(rest, first.id)
  end

  def chain_valid?(_other, _opts), do: false

  defp links?([], _previous_id), do: true
  defp links?([%{previous: previous} = receipt | rest], previous), do: links?(rest, receipt.id)
  defp links?(_broken, _previous_id), do: false

  defp normalize_previous(nil), do: nil
  defp normalize_previous(%__MODULE__{id: id}), do: id
  defp normalize_previous(id) when is_binary(id), do: id
  defp normalize_previous(other), do: inspect(other)

  defp valid_id?(id), do: is_binary(id) and Regex.match?(@id_pattern, id)

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_REPLAY, subject, detail, evidence)}
  end
end
