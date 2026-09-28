defmodule AshR2RML.VKG.QueryPlan do
  @moduledoc """
  Deterministic, observe-only plan for one federated virtual graph query.
  """

  alias AshR2RML.Refusal

  @enforce_keys [:id, :catalog_sha256, :contract_ids, :stages, :sha256]
  defstruct [
    :id,
    :catalog_sha256,
    :contract_ids,
    :stages,
    :sha256,
    max_rows: 50_000,
    timeout_ms: 30_000,
    merge: :union,
    authority: :NONE
  ]

  @type stage :: %{
          required(:contract_id) => String.t(),
          required(:source) => String.t(),
          required(:graph) => String.t(),
          required(:mapping_path) => String.t(),
          required(:query_path) => String.t(),
          required(:mapping_sha256) => String.t(),
          required(:query_sha256) => String.t(),
          required(:source_sha256) => String.t()
        }

  @type t :: %__MODULE__{}

  @spec new(String.t(), [String.t()], [stage()], keyword()) :: {:ok, t()} | {:error, Refusal.t()}
  def new(catalog_sha256, contract_ids, stages, opts \\ []) do
    max_rows = Keyword.get(opts, :max_rows, 50_000)
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    merge = Keyword.get(opts, :merge, :union)

    with :ok <- digest?(catalog_sha256, :catalog_sha256),
         :ok <- non_empty_ids?(contract_ids),
         :ok <- stages_match?(contract_ids, stages),
         :ok <- positive_integer?(max_rows, :max_rows),
         :ok <- positive_integer?(timeout_ms, :timeout_ms),
         :ok <- merge_mode?(merge) do
      core = {catalog_sha256, contract_ids, canonical_stages(stages), max_rows, timeout_ms, merge}
      sha256 = hash(core)
      id = "vkg-plan-" <> binary_part(sha256, 0, 16)

      {:ok,
       %__MODULE__{
         id: id,
         catalog_sha256: catalog_sha256,
         contract_ids: contract_ids,
         stages: stages,
         sha256: sha256,
         max_rows: max_rows,
         timeout_ms: timeout_ms,
         merge: merge,
         authority: :NONE
       }}
    end
  end

  @spec verify(t()) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{} = plan) do
    core =
      {plan.catalog_sha256, plan.contract_ids, canonical_stages(plan.stages), plan.max_rows,
       plan.timeout_ms, plan.merge}

    cond do
      plan.authority != :NONE ->
        refusal(:authority, "VKG query plan cannot carry actuation authority", %{authority: plan.authority})

      hash(core) != plan.sha256 ->
        refusal(:sha256, "VKG query plan digest does not match its contents", %{expected: plan.sha256, observed: hash(core)})

      true ->
        :ok
    end
  end

  defp canonical_stages(stages) do
    Enum.map(stages, fn stage ->
      stage |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    end)
  end

  defp digest?(value, _field) when is_binary(value) and byte_size(value) == 64 do
    if String.match?(value, ~r/\A[0-9a-f]{64}\z/), do: :ok, else: refusal(:digest, "invalid sha256", %{value: value})
  end

  defp digest?(value, field), do: refusal(field, "expected lowercase sha256", %{value: inspect(value)})

  defp non_empty_ids?(ids) when is_list(ids) and ids != [] and length(ids) == length(Enum.uniq(ids)), do: :ok
  defp non_empty_ids?(ids), do: refusal(:contract_ids, "query plan requires unique contract ids", %{ids: inspect(ids)})

  defp stages_match?(ids, stages) when is_list(stages) do
    stage_ids = Enum.map(stages, &Map.get(&1, :contract_id))

    if stage_ids == ids do
      :ok
    else
      refusal(:stages, "query stages must preserve exact requested contract order", %{contract_ids: ids, stage_ids: stage_ids})
    end
  end

  defp stages_match?(_ids, stages), do: refusal(:stages, "query stages must be a list", %{stages: inspect(stages)})

  defp positive_integer?(value, _field) when is_integer(value) and value > 0, do: :ok
  defp positive_integer?(value, field), do: refusal(field, "query bound must be a positive integer", %{value: value})

  defp merge_mode?(mode) when mode in [:union, :by_subject], do: :ok
  defp merge_mode?(mode), do: refusal(:merge, "unsupported VKG merge mode", %{merge: mode})

  defp hash(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_QUERY_PLAN, subject, detail, evidence)}
  end
end
