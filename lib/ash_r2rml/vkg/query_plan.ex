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
    :ontology_sha256,
    max_rows: 50_000,
    timeout_ms: 30_000,
    merge: :union,
    capability: :select,
    capabilities: [],
    authority: :NONE
  ]

  # Filesystem locations are execution inputs, not identity: they are excluded
  # from the plan digest so identical semantic plans hash identically on any host.
  @path_keys [:mapping_path, :query_path, :ontology_path]

  @type stage :: %{
          required(:contract_id) => String.t(),
          required(:source) => String.t(),
          required(:graph) => String.t(),
          required(:mapping_path) => String.t(),
          required(:query_path) => String.t(),
          required(:mapping_sha256) => String.t(),
          required(:query_sha256) => String.t(),
          required(:source_sha256) => String.t(),
          optional(:contract_digest) => String.t(),
          optional(:ontology_sha256) => String.t() | nil,
          optional(:ontology_path) => String.t() | nil,
          optional(:subject_template) => String.t(),
          optional(:version) => String.t(),
          optional(:capabilities) => [atom()]
        }

  @type t :: %__MODULE__{}

  @spec new(String.t(), [String.t()], [stage()], keyword()) ::
          {:ok, t()} | {:error, Refusal.t()}
  def new(catalog_sha256, contract_ids, stages, opts \\ [])

  def new(catalog_sha256, contract_ids, stages, opts) when is_list(opts) do
    max_rows = Keyword.get(opts, :max_rows, 50_000)
    timeout_ms = Keyword.get(opts, :timeout_ms, 30_000)
    merge = Keyword.get(opts, :merge, :union)
    capability = Keyword.get(opts, :capability, :select)

    with :ok <- digest?(catalog_sha256, :catalog_sha256),
         :ok <- non_empty_ids?(contract_ids),
         :ok <- stages_match?(contract_ids, stages),
         :ok <- stage_capabilities?(stages),
         :ok <- positive_integer?(max_rows, :max_rows),
         :ok <- positive_integer?(timeout_ms, :timeout_ms),
         :ok <- merge_mode?(merge),
         :ok <- capability?(capability) do
      plan = %__MODULE__{
        id: "",
        catalog_sha256: catalog_sha256,
        contract_ids: contract_ids,
        stages: stages,
        sha256: "",
        ontology_sha256: ontology_binding(stages),
        max_rows: max_rows,
        timeout_ms: timeout_ms,
        merge: merge,
        capability: capability,
        capabilities: common_capabilities(stages),
        authority: :NONE
      }

      sha256 = hash(core(plan))
      {:ok, %{plan | sha256: sha256, id: plan_id(sha256)}}
    end
  end

  def new(_catalog_sha256, _contract_ids, _stages, opts),
    do: refusal(:options, "query plan options must be a keyword list", %{value: inspect(opts)})

  @spec verify(t()) :: :ok | {:error, Refusal.t()}
  def verify(%__MODULE__{} = plan) do
    with :ok <- authority?(plan.authority),
         :ok <- digest?(plan.catalog_sha256, :catalog_sha256),
         :ok <- non_empty_ids?(plan.contract_ids),
         :ok <- stages_match?(plan.contract_ids, plan.stages),
         :ok <- stage_capabilities?(plan.stages),
         :ok <- positive_integer?(plan.max_rows, :max_rows),
         :ok <- positive_integer?(plan.timeout_ms, :timeout_ms),
         :ok <- merge_mode?(plan.merge),
         :ok <- capability?(plan.capability),
         :ok <- digest?(plan.sha256, :sha256) do
      observed = hash(core(plan))

      cond do
        observed != plan.sha256 ->
          refusal(:sha256, "VKG query plan digest does not match its contents", %{
            expected: plan.sha256,
            observed: observed
          })

        plan.id != plan_id(plan.sha256) ->
          refusal(:id, "VKG query plan id does not derive from its digest", %{id: plan.id})

        true ->
          :ok
      end
    end
  end

  def verify(other),
    do: refusal(:plan, "VKG query plan must be a QueryPlan struct", %{value: inspect(other)})

  defp plan_id(sha256), do: "vkg-plan-" <> binary_part(sha256, 0, 16)

  defp core(plan) do
    {plan.catalog_sha256, plan.contract_ids, canonical_stages(plan.stages), plan.max_rows, plan.timeout_ms, plan.merge,
     plan.capability, plan.capabilities, plan.ontology_sha256}
  end

  defp canonical_stages(stages) do
    Enum.map(stages, fn stage ->
      stage
      |> Map.drop(@path_keys)
      |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    end)
  end

  defp ontology_binding(stages) do
    digests = Enum.map(stages, &Map.get(&1, :ontology_sha256))
    if Enum.all?(digests, &is_nil/1), do: nil, else: hash(digests)
  end

  defp common_capabilities(stages) do
    stages
    |> Enum.map(&(&1 |> Map.get(:capabilities, []) |> Enum.sort()))
    |> Enum.reduce(fn caps, acc -> Enum.filter(acc, &(&1 in caps)) end)
  end

  defp authority?(:NONE), do: :ok

  defp authority?(authority),
    do: refusal(:authority, "VKG query plan cannot carry actuation authority", %{authority: authority})

  defp capability?(capability) do
    if capability in AshR2RML.VKG.Contract.capability_allowlist() do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_CAPABILITY,
         :capability,
         "requested VKG capability is outside the observe-only allowlist",
         %{capability: inspect(capability)}
       )}
    end
  end

  defp digest?(value, _field) when is_binary(value) and byte_size(value) == 64 do
    if String.match?(value, ~r/\A[0-9a-f]{64}\z/),
      do: :ok,
      else: refusal(:digest, "invalid sha256", %{value: value})
  end

  defp digest?(value, field),
    do: refusal(field, "expected lowercase sha256", %{value: inspect(value)})

  defp non_empty_ids?(ids) when is_list(ids) and ids != [] do
    if length(ids) == length(Enum.uniq(ids)),
      do: :ok,
      else: refusal(:contract_ids, "query plan requires unique contract ids", %{ids: inspect(ids)})
  end

  defp non_empty_ids?(ids),
    do: refusal(:contract_ids, "query plan requires unique contract ids", %{ids: inspect(ids)})

  defp stages_match?(ids, stages) when is_list(stages) do
    stage_ids = Enum.map(stages, &if(is_map(&1), do: Map.get(&1, :contract_id), else: nil))

    if stage_ids == ids do
      :ok
    else
      refusal(:stages, "query stages must preserve exact requested contract order", %{
        contract_ids: ids,
        stage_ids: stage_ids
      })
    end
  end

  defp stages_match?(_ids, stages),
    do: refusal(:stages, "query stages must be a list", %{stages: inspect(stages)})

  defp stage_capabilities?(stages) do
    allowed = AshR2RML.VKG.Contract.capability_allowlist()

    invalid =
      Enum.flat_map(stages, fn stage ->
        case Map.get(stage, :capabilities, []) do
          caps when is_list(caps) -> Enum.reject(caps, &(&1 in allowed))
          other -> [other]
        end
      end)

    if invalid == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_CAPABILITY,
         :stage_capabilities,
         "VKG stage capabilities are outside the observe-only allowlist",
         %{invalid: Enum.map(invalid, &inspect/1), allowed: allowed}
       )}
    end
  end

  defp positive_integer?(value, _field) when is_integer(value) and value > 0, do: :ok

  defp positive_integer?(value, field),
    do: refusal(field, "query bound must be a positive integer", %{value: value})

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
