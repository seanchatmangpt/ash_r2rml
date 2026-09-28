defmodule AshR2RML.VKG.Executor do
  @moduledoc """
  Executes an admitted VKG query plan with per-stage failure isolation.

  Any refused stage refuses the whole exact-subject query result. Successful
  stages are never silently returned as though they represented the requested
  federation.

  Engine transport order is not semantic identity. Successful observations are
  rebound to a canonical digest over the exact stage identity plus normalized
  row set. Raw engine-byte identity remains available as output_sha256.
  """

  alias AshR2RML.OBDA.Observation
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Provenance, QueryPlan, Result}

  @type observation_by_contract :: %{optional(String.t()) => map()}

  @spec execute(QueryPlan.t(), keyword()) ::
          {:ok, Result.t(), observation_by_contract()} | {:error, Refusal.t()}
  def execute(%QueryPlan{} = plan, opts \\ []) do
    engine = Keyword.get(opts, :engine, AshR2RML.VKG.Engine.Ontop)
    # Live standing is only ever granted to the built-in Ontop engine running a
    # real process; the caller-controlled :engine option cannot self-assert it.
    trusted? = engine == AshR2RML.VKG.Engine.Ontop and not Keyword.has_key?(opts, :runner)
    run(plan, engine, opts, trusted?)
  end

  @doc false
  # Replay path: recorded observations are fed back through the same executor and
  # standing is re-derived from the recorded evidence itself.
  @spec replay(QueryPlan.t(), module(), keyword()) ::
          {:ok, Result.t(), observation_by_contract()} | {:error, Refusal.t()}
  def replay(%QueryPlan{} = plan, engine, opts), do: run(plan, engine, opts, true)

  defp run(plan, engine, opts, trusted?) do
    with :ok <- check_engine(engine),
         :ok <- QueryPlan.verify(plan),
         {:ok, rows, observations} <- run_stages(plan, engine, opts),
         :ok <- enforce_result_bound(rows, plan.max_rows) do
      standing = aggregate_standing(observations, trusted?)
      {:ok, Result.build(plan.sha256, merge(rows, plan.merge), standing), observations}
    end
  end

  defp check_engine(engine) do
    if is_atom(engine) and not is_nil(engine) and Code.ensure_loaded?(engine) and
         function_exported?(engine, :execute, 2) do
      :ok
    else
      {:error,
       Refusal.new(:REFUSED_VKG_EXECUTION, :engine, "VKG :engine must be a module exporting execute/2", %{
         engine: inspect(engine)
       })}
    end
  end

  # A result may only claim live observation when the engine is trusted and every
  # stage was observed by a real system process; any injected/test-double
  # evidence weakens the whole.
  defp aggregate_standing(observations, trusted?) do
    live? =
      trusted? and observations != %{} and
        Enum.all?(observations, fn {_id, obs} ->
          obs.evidence_kind == :system_process and obs.standing == :obda_query_observed
        end)

    if live?, do: :observed_not_actuated, else: :test_double_only
  end

  defp run_stages(plan, engine, opts) do
    verify_files? =
      Keyword.get(
        opts,
        :verify_files,
        engine == AshR2RML.VKG.Engine.Ontop and not Keyword.has_key?(opts, :runner)
      )

    Enum.reduce_while(plan.stages, {:ok, [], %{}, 0}, fn stage, {:ok, rows, observations, count} ->
      stage_opts =
        opts
        |> Keyword.put(:timeout_ms, plan.timeout_ms)
        |> Keyword.put(:max_rows, plan.max_rows)

      with :ok <- if(verify_files?, do: verify_files(stage), else: :ok),
           {:ok, observation} <- call_engine(engine, stage, stage_opts),
           :ok <- validate_observation(observation, stage),
           :ok <- check_drift(observation, stage),
           :ok <- check_running_bound(count + length(observation.rows), plan.max_rows) do
        observation = canonicalize_observation(observation, stage)

        observed_rows =
          Enum.map(observation.rows, &Provenance.attach(&1, stage, Map.from_struct(observation)))

        {:cont,
         {:ok, rows ++ observed_rows, Map.put(observations, stage.contract_id, observation),
          count + length(observed_rows)}}
      else
        {:error, %Refusal{code: code} = refusal}
        when code in [:REFUSED_RESOURCE_BOUND, :REFUSED_VKG_SOURCE_DRIFT] ->
          {:halt, {:error, refusal}}

        {:error, %Refusal{} = refusal} ->
          {:halt, {:error, stage_refusal(stage, refusal)}}
      end
    end)
    |> case do
      {:ok, rows, observations, _count} -> {:ok, rows, observations}
      {:error, _} = error -> error
    end
  end

  defp call_engine(engine, stage, stage_opts) do
    case safe_engine_call(engine, stage, stage_opts) do
      {:raised, detail} ->
        {:error, Refusal.new(:REFUSED_VKG_EXECUTION, stage.contract_id, "VKG engine raised", %{error: detail})}

      {:ok, observation} ->
        {:ok, observation}

      {:error, %{} = observation} ->
        {:error,
         Map.get(observation, :refusal) ||
           Refusal.new(
             :REFUSED_VKG_EXECUTION,
             stage.contract_id,
             "VKG stage execution failed",
             %{standing: Map.get(observation, :standing)}
           )}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_VKG_EXECUTION,
           stage.contract_id,
           "VKG engine returned a malformed result",
           %{returned: inspect(other, limit: 5, printable_limit: 200)}
         )}
    end
  end

  defp safe_engine_call(engine, stage, stage_opts) do
    engine.execute(stage, stage_opts)
  rescue
    error -> {:raised, Exception.message(error)}
  catch
    kind, reason -> {:raised, inspect({kind, reason}, limit: 5, printable_limit: 200)}
  end

  defp stage_refusal(stage, refusal) do
    Refusal.new(
      :REFUSED_VKG_EXECUTION,
      stage.contract_id,
      "exact-subject VKG stage was refused",
      %{cause: refusal, source: stage.source, graph: stage.graph}
    )
  end

  defp validate_observation(%Observation{rows: rows} = obs, stage) when is_list(rows) do
    cond do
      not Enum.all?(rows, &(is_map(&1) and not is_struct(&1))) ->
        malformed(stage, "engine rows must all be plain maps", %{})

      obs.bounded? != true ->
        malformed(stage, "engine observation was not bounded", %{})

      not is_nil(obs.row_count) and obs.row_count != length(rows) ->
        malformed(stage, "engine row_count does not match its rows", %{
          claimed: obs.row_count,
          actual: length(rows)
        })

      true ->
        :ok
    end
  end

  defp validate_observation(other, stage),
    do:
      malformed(stage, "engine observation is not an OBDA observation with a row list", %{
        returned: inspect(other, limit: 5, printable_limit: 200)
      })

  defp malformed(stage, detail, evidence),
    do: {:error, Refusal.new(:REFUSED_VKG_EXECUTION, stage.contract_id, detail, evidence)}

  defp check_drift(observation, stage) do
    drifted =
      for {field, obs_value} <- [
            mapping_sha256: observation.mapping_sha256,
            query_sha256: observation.query_sha256
          ],
          not is_nil(obs_value),
          obs_value != Map.get(stage, field),
          do: field

    drift_result(drifted, stage, %{
      observed: %{mapping_sha256: observation.mapping_sha256, query_sha256: observation.query_sha256},
      admitted: %{mapping_sha256: stage.mapping_sha256, query_sha256: stage.query_sha256}
    })
  end

  defp verify_files(stage) do
    drifted =
      for {field, path} <- [mapping_sha256: stage.mapping_path, query_sha256: stage.query_path],
          file_sha(path) != Map.get(stage, field),
          do: field

    drift_result(drifted, stage, %{phase: :pre_execution})
  end

  defp file_sha(path) do
    case File.read(path) do
      {:ok, bytes} -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      {:error, _} -> nil
    end
  end

  defp drift_result([], _stage, _evidence), do: :ok

  defp drift_result(fields, stage, evidence) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_SOURCE_DRIFT,
       stage.contract_id,
       "VKG stage artifacts drifted from the admitted digests",
       Map.put(evidence, :fields, fields)
     )}
  end

  defp check_running_bound(count, max_rows) when count <= max_rows, do: :ok
  defp check_running_bound(count, max_rows), do: {:error, bound_refusal(count, max_rows)}

  defp canonicalize_observation(observation, stage) do
    rows =
      observation.rows
      |> Enum.map(&canonical_term/1)
      |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))

    identity = {
      stage.contract_id,
      stage.source_sha256,
      stage.mapping_sha256,
      stage.query_sha256,
      rows
    }

    semantic_sha256 =
      identity
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %{observation | observation_sha256: semantic_sha256}
  end

  defp canonical_term(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_term(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> canonical_term()
  defp canonical_term(value), do: value

  defp enforce_result_bound(rows, max_rows) do
    if length(rows) <= max_rows, do: :ok, else: {:error, bound_refusal(length(rows), max_rows)}
  end

  defp bound_refusal(observed, limit) do
    Refusal.new(
      :REFUSED_RESOURCE_BOUND,
      :vkg_rows,
      "federated result exceeded the admitted row bound",
      %{observed: observed, limit: limit}
    )
  end

  defp merge(rows, :union), do: Enum.uniq_by(rows, &row_identity/1)

  defp merge(rows, :by_subject) do
    rows
    |> Enum.sort_by(&row_identity/1)
    |> Enum.group_by(&get_in(&1, ["_vkg", "subject"]))
    |> Enum.sort_by(fn {subject, _} -> :erlang.term_to_binary(subject, [:deterministic]) end)
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

  # Members arrive sorted by row digest. Colliding keys with differing values
  # become a sorted multi-valued list, so no source value is dropped.
  defp merge_subject(rows) do
    metadata = Enum.map(rows, &Map.fetch!(&1, "_vkg"))

    payload =
      rows
      |> Enum.map(fn row ->
        row |> Map.delete("_vkg") |> Map.new(fn {k, v} -> {to_string(k), v} end)
      end)
      |> Enum.reduce(%{}, fn row, acc ->
        Map.merge(acc, row, fn _key, left, right -> merge_values(left, right) end)
      end)

    contract_ids = metadata |> Enum.map(& &1["contract_id"]) |> Enum.uniq() |> Enum.sort()

    Map.put(payload, "_vkg", %{
      "subject" => get_in(hd(rows), ["_vkg", "subject"]),
      "contract_id" => hd(contract_ids),
      "federated_sources" => contract_ids,
      "source_receipts" => Enum.sort_by(metadata, &{&1["contract_id"], &1["row_sha256"]})
    })
  end

  defp merge_values(same, same), do: same

  defp merge_values(left, right) do
    (List.wrap(left) ++ List.wrap(right))
    |> Enum.uniq()
    |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))
    |> case do
      [single] -> single
      many -> many
    end
  end
end
