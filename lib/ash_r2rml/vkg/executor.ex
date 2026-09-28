defmodule AshR2RML.VKG.Executor do
  @moduledoc """
  Executes an admitted VKG query plan with per-stage failure isolation.

  Any refused stage refuses the whole exact-subject query result. Successful
  stages are never silently returned as though they represented the requested
  federation.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Provenance, QueryPlan, Result}

  @type observation_by_contract :: %{optional(String.t()) => map()}

  @spec execute(QueryPlan.t(), keyword()) ::
          {:ok, Result.t(), observation_by_contract()} | {:error, Refusal.t()}
  def execute(%QueryPlan{} = plan, opts \\ []) do
    engine = Keyword.get(opts, :engine, AshR2RML.VKG.Engine.Ontop)

    with :ok <- QueryPlan.verify(plan),
         {:ok, rows, observations} <- run_stages(plan, engine, opts),
         :ok <- enforce_result_bound(rows, plan.max_rows) do
      {:ok, Result.build(plan.sha256, merge(rows, plan.merge)), observations}
    end
  end

  defp run_stages(plan, engine, opts) do
    Enum.reduce_while(plan.stages, {:ok, [], %{}}, fn stage, {:ok, rows, observations} ->
      stage_opts =
        opts
        |> Keyword.put(:timeout_ms, plan.timeout_ms)
        |> Keyword.put(:max_rows, plan.max_rows)

      case engine.execute(stage, stage_opts) do
        {:ok, observation} ->
          observed_rows =
            observation.rows
            |> Enum.map(&Provenance.attach(&1, stage, Map.from_struct(observation)))

          observations = Map.put(observations, stage.contract_id, observation)
          {:cont, {:ok, rows ++ observed_rows, observations}}

        {:error, observation} ->
          refusal =
            Map.get(observation, :refusal) ||
              Refusal.new(
                :REFUSED_VKG_EXECUTION,
                stage.contract_id,
                "VKG stage execution failed",
                %{standing: Map.get(observation, :standing)}
              )

          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_VKG_EXECUTION,
              stage.contract_id,
              "exact-subject VKG stage was refused",
              %{cause: refusal, source: stage.source, graph: stage.graph}
            )}}
      end
    end)
  end

  defp enforce_result_bound(rows, max_rows) do
    if length(rows) <= max_rows do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_RESOURCE_BOUND,
         :vkg_rows,
         "federated result exceeded the admitted row bound",
         %{observed: length(rows), limit: max_rows}
       )}
    end
  end

  defp merge(rows, :union), do: Enum.uniq_by(rows, &row_identity/1)

  defp merge(rows, :by_subject) do
    rows
    |> Enum.group_by(&get_in(&1, ["_vkg", "subject"]))
    |> Enum.flat_map(fn
      {nil, members} -> members
      {_subject, [single]} -> [single]
      {_subject, members} -> [merge_subject(members)]
    end)
  end

  defp row_identity(row) do
    get_in(row, ["_vkg", "row_sha256"]) ||
      :erlang.term_to_binary(row, [:deterministic]) |> then(&:crypto.hash(:sha256, &1))
  end

  defp merge_subject(rows) do
    metadata = Enum.map(rows, &Map.fetch!(&1, "_vkg"))

    rows
    |> Enum.map(&Map.delete(&1, "_vkg"))
    |> Enum.reduce(%{}, &Map.merge(&2, &1))
    |> Map.put("_vkg", %{
      "subject" => get_in(hd(rows), ["_vkg", "subject"]),
      "federated_sources" => Enum.map(metadata, & &1["contract_id"]) |> Enum.uniq() |> Enum.sort(),
      "source_receipts" => metadata
    })
  end
end
