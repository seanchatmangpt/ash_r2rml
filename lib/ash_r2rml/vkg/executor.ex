defmodule AshR2RML.VKG.Executor do
  @moduledoc """
  Executes an admitted VKG query plan with per-stage failure isolation.

  Any refused stage refuses the whole exact-subject query result. Successful
  stages are never silently returned as though they represented the requested
  federation.

  Engine transport order is not semantic identity. Successful observations are
  rebound to a canonical digest (the injective canonical JSON encoding of
  `AshR2RML.VKG.Serializer`, never the BEAM term format) over the exact stage
  identity plus the row set. Raw engine-byte identity remains available as
  output_sha256.
  """

  alias AshR2RML.OBDA.Observation
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Catalog, Planner, Provenance, QueryPlan, Registry, Result, Serializer}

  @type observation_by_contract :: %{optional(String.t()) => map()}

  @doc """
  Executes an admitted plan.

  Before any engine call the plan is bound to a catalog: the `:catalog` option, or
  the catalog the `AshR2RML.VKG.Planner` recorded in `plan.catalog`. Every stage
  (contract digest, source/mapping/query/ontology digests, paths, capabilities) must
  equal the stage the catalog's admitted contract produces, otherwise the plan is
  refused with `REFUSED_VKG_SOURCE_DRIFT` (digest mismatch) or
  `REFUSED_VKG_QUERY_PLAN` (any other mismatch, or no catalog binding at all).

  When files are verified (the default for the live Ontop engine, or
  `verify_files: true`) each stage's mapping, query and ontology bytes are read
  exactly once, hashed, compared with the admitted digests and copied into a
  private temporary directory. The engine only ever sees those snapshot paths, so
  a file swapped after hashing cannot reach the engine. The directory is removed
  afterwards. The plan's requested capability is forwarded to the engine as
  `:required_capabilities`.
  """
  @spec execute(QueryPlan.t(), keyword()) ::
          {:ok, Result.t(), observation_by_contract()} | {:error, Refusal.t()}
  def execute(plan, opts \\ [])

  def execute(%QueryPlan{} = plan, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      engine = Keyword.get(opts, :engine, AshR2RML.VKG.Engine.Ontop)
      # Live standing is only ever granted to the built-in Ontop engine running a
      # real process; the caller-controlled :engine option cannot self-assert it.
      trusted? = engine == AshR2RML.VKG.Engine.Ontop and not Keyword.has_key?(opts, :runner)
      run(plan, engine, opts, trusted?, :execute)
    else
      plan_refusal(:options, "VKG executor options must be a keyword list", %{value: inspect(opts)})
    end
  end

  def execute(%QueryPlan{}, opts),
    do: plan_refusal(:options, "VKG executor options must be a keyword list", %{value: inspect(opts)})

  def execute(other, _opts), do: QueryPlan.verify(other)

  @doc """
  Replays recorded observations through the executor and verifies them.

  `engine` must accept `recorded_observations` (see `AshR2RML.VKG.Replay`). The
  recorded evidence is not trusted: each observation must be an OBDA observation
  whose plan-bound digests match the stage, whose `observation_sha256` equals the
  digest recomputed from its own rows and the stage identity (otherwise
  `REFUSED_VKG_REPLAY`), and whose live claim is only honoured for an `:ontop`
  system process observation with `:obda_query_observed` standing. Bounds, merge
  and provenance are re-applied exactly as in `execute/2`. No files are read and
  no catalog binding is required, because nothing is executed; the plan itself is
  still fully verified.
  """
  @spec replay(QueryPlan.t(), module(), keyword()) ::
          {:ok, Result.t(), observation_by_contract()} | {:error, Refusal.t()}
  def replay(%QueryPlan{} = plan, engine, opts) do
    if is_list(opts) and Keyword.keyword?(opts),
      do: run(plan, engine, opts, true, :replay),
      else: plan_refusal(:options, "VKG executor options must be a keyword list", %{value: inspect(opts)})
  end

  def replay(other, _engine, _opts), do: QueryPlan.verify(other)

  defp run(plan, engine, opts, trusted?, mode) do
    with :ok <- check_engine(engine),
         :ok <- QueryPlan.verify(plan),
         :ok <- if(mode == :execute, do: bind_catalog(plan, opts), else: :ok),
         {:ok, rows, observations} <- run_stages(plan, engine, opts, mode),
         :ok <- enforce_result_bound(rows, plan.max_rows) do
      standing = aggregate_standing(observations, trusted?)
      {:ok, Result.build(plan.sha256, merge(rows, plan.merge), standing), observations}
    end
  end

  # -- catalog binding -----------------------------------------------------

  defp bind_catalog(plan, opts) do
    case Keyword.get(opts, :catalog) || plan.catalog do
      %Catalog{} = catalog ->
        with :ok <- catalog_intact(catalog),
             :ok <- catalog_matches_plan(catalog, plan) do
          stages_match_catalog(plan, catalog)
        end

      nil ->
        plan_refusal(
          :catalog,
          "VKG plan is not bound to an admitted catalog; build it with AshR2RML.VKG.Planner or pass :catalog",
          %{plan: plan.id}
        )

      other ->
        plan_refusal(:catalog, "VKG :catalog must be an admitted catalog", %{got: inspect(other)})
    end
  end

  defp catalog_intact(%Catalog{contracts: contracts, sha256: sha256})
       when is_map(contracts) and map_size(contracts) > 0 do
    with {:ok, registry} <- Registry.admit(Map.values(contracts)),
         true <- registry == contracts and Registry.digest(registry) == sha256 do
      :ok
    else
      {:error, %Refusal{} = cause} ->
        plan_refusal(:catalog, "VKG catalog does not re-admit", %{cause: cause})

      _ ->
        plan_refusal(:catalog, "VKG catalog digest does not match its contracts", %{})
    end
  end

  defp catalog_intact(_catalog), do: plan_refusal(:catalog, "VKG catalog carries no admitted contracts", %{})

  defp catalog_matches_plan(catalog, plan) do
    if catalog.sha256 == plan.catalog_sha256 do
      :ok
    else
      plan_refusal(:catalog, "VKG plan was built from a different catalog", %{
        catalog: catalog.sha256,
        plan: plan.catalog_sha256
      })
    end
  end

  @digest_fields [:contract_digest, :source_sha256, :mapping_sha256, :query_sha256, :ontology_sha256]

  defp stages_match_catalog(plan, catalog) do
    Enum.reduce_while(plan.stages, :ok, fn stage, :ok ->
      case check_stage_binding(stage, plan, catalog) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_stage_binding(stage, plan, catalog) do
    with {:ok, contract} <- fetch_bound_contract(catalog, stage) do
      expected = Planner.stage_for(contract)

      differing =
        (Map.keys(expected) ++ Map.keys(stage))
        |> Enum.uniq()
        |> Enum.filter(&(Map.get(expected, &1) != Map.get(stage, &1)))

      cond do
        differing == [] and plan.capability in expected.capabilities ->
          :ok

        differing == [] ->
          plan_refusal(stage.contract_id, "plan capability is not admitted by the bound contract", %{
            capability: plan.capability
          })

        Enum.any?(differing, &(&1 in @digest_fields)) ->
          {:error,
           Refusal.new(
             :REFUSED_VKG_SOURCE_DRIFT,
             stage.contract_id,
             "VKG stage digests do not match the bound catalog contract",
             %{fields: Enum.filter(differing, &(&1 in @digest_fields)), phase: :catalog_binding}
           )}

        true ->
          plan_refusal(stage.contract_id, "VKG stage does not match the bound catalog contract", %{
            fields: differing,
            phase: :catalog_binding
          })
      end
    end
  end

  defp fetch_bound_contract(catalog, stage) do
    case Catalog.fetch(catalog, Map.get(stage, :contract_id)) do
      {:ok, contract} ->
        {:ok, contract}

      {:error, %Refusal{} = cause} ->
        plan_refusal(Map.get(stage, :contract_id), "VKG stage contract is not in the bound catalog", %{cause: cause})
    end
  end

  defp plan_refusal(subject, detail, evidence),
    do: {:error, Refusal.new(:REFUSED_VKG_QUERY_PLAN, subject, detail, evidence)}

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
          obs.evidence_kind == :system_process and obs.standing == :obda_query_observed and obs.system == :ontop
        end)

    if live?, do: :observed_not_actuated, else: :test_double_only
  end

  defp run_stages(plan, engine, opts, mode) do
    verify_files? =
      mode == :execute and
        Keyword.get(
          opts,
          :verify_files,
          engine == AshR2RML.VKG.Engine.Ontop and not Keyword.has_key?(opts, :runner)
        )

    required =
      opts |> Keyword.get(:required_capabilities, []) |> List.wrap() |> Kernel.++([plan.capability]) |> Enum.uniq()

    Enum.reduce_while(plan.stages, {:ok, [], %{}, 0}, fn stage, {:ok, rows, observations, count} ->
      stage_opts =
        opts
        |> Keyword.put(:timeout_ms, plan.timeout_ms)
        |> Keyword.put(:max_rows, plan.max_rows)
        |> Keyword.put(:required_capabilities, required)

      case run_stage(stage, engine, stage_opts, mode, verify_files?, count, plan.max_rows) do
        {:ok, observation, observed_rows} ->
          {:cont,
           {:ok, rows ++ observed_rows, Map.put(observations, stage.contract_id, observation),
            count + length(observed_rows)}}

        {:error, %Refusal{code: code} = refusal}
        when code in [:REFUSED_RESOURCE_BOUND, :REFUSED_VKG_SOURCE_DRIFT, :REFUSED_VKG_REPLAY] ->
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

  defp run_stage(stage, engine, stage_opts, mode, verify_files?, count, max_rows) do
    with_stage_inputs(stage, verify_files?, fn engine_stage ->
      with {:ok, observation} <- call_engine(engine, engine_stage, stage_opts),
           :ok <- validate_observation(observation, stage),
           :ok <- check_drift(observation, stage),
           :ok <- check_running_bound(count + length(observation.rows), max_rows),
           :ok <- if(mode == :replay, do: check_recorded_digest(observation, stage), else: :ok) do
        observation = canonicalize_observation(observation, stage)

        observed_rows =
          Enum.map(observation.rows, &Provenance.attach(&1, stage, Map.from_struct(observation)))

        {:ok, observation, observed_rows}
      end
    end)
  end

  # -- exact-byte input snapshot -------------------------------------------

  defp with_stage_inputs(stage, false, fun), do: fun.(stage)

  defp with_stage_inputs(stage, true, fun) do
    with {:ok, engine_stage, dir} <- snapshot_stage(stage) do
      try do
        fun.(engine_stage)
      after
        File.rm_rf(dir)
      end
    end
  end

  # Reads each artifact exactly once, hashes those very bytes, and hands the engine
  # a private copy of the hashed bytes. Nothing the engine reads can differ from
  # what was compared with the admitted digest.
  defp snapshot_stage(stage) do
    artifacts =
      [{:mapping_sha256, :mapping_path, "mapping"}, {:query_sha256, :query_path, "query"}] ++
        if(is_nil(stage.ontology_path) and is_nil(Map.get(stage, :ontology_sha256)),
          do: [],
          else: [{:ontology_sha256, :ontology_path, "ontology"}]
        )

    loaded =
      Enum.map(artifacts, fn {digest_field, path_field, name} ->
        {digest_field, path_field, name, read_bytes(Map.get(stage, path_field))}
      end)

    drifted =
      for {digest_field, _path_field, _name, bytes} <- loaded,
          is_nil(bytes) or sha256(bytes) != Map.get(stage, digest_field),
          do: digest_field

    case drift_result(drifted, stage, %{phase: :pre_execution}) do
      :ok -> write_snapshot(stage, loaded)
      error -> error
    end
  end

  defp read_bytes(path) when is_binary(path) do
    case File.read(path) do
      {:ok, bytes} -> bytes
      {:error, _} -> nil
    end
  end

  defp read_bytes(_path), do: nil

  defp write_snapshot(stage, loaded) do
    dir = Path.join(System.tmp_dir!(), "ash_r2rml_vkg_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower))

    with :ok <- File.mkdir(dir),
         :ok <- File.chmod(dir, 0o700),
         {:ok, paths} <- write_files(dir, stage, loaded) do
      {:ok, Map.merge(stage, paths), dir}
    else
      {:error, reason} ->
        File.rm_rf(dir)

        {:error,
         Refusal.new(:REFUSED_VKG_EXECUTION, stage.contract_id, "could not snapshot VKG stage inputs", %{
           reason: inspect(reason)
         })}
    end
  end

  defp write_files(dir, stage, loaded) do
    Enum.reduce_while(loaded, {:ok, %{}}, fn {_digest_field, path_field, name, bytes}, {:ok, acc} ->
      target = Path.join(dir, name <> safe_extension(Map.get(stage, path_field)))

      with :ok <- File.write(target, bytes),
           :ok <- File.chmod(target, 0o400) do
        {:cont, {:ok, Map.put(acc, path_field, target)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # Ontop selects parsers by extension, so the snapshot keeps a sanitized one.
  defp safe_extension(path) when is_binary(path) do
    ext = Path.extname(path)
    if Regex.match?(~r/\A\.[A-Za-z0-9]{1,12}\z/, ext), do: ext, else: ""
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

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

  # Semantic identity: exact stage identity plus the row set under the canonical
  # (injective) JSON encoding, independent of engine transport order.
  defp semantic_sha256(observation, stage) do
    Serializer.digest(%{
      "kind" => "vkg.observation",
      "contract_id" => stage.contract_id,
      "source_sha256" => stage.source_sha256,
      "mapping_sha256" => stage.mapping_sha256,
      "query_sha256" => stage.query_sha256,
      "rows" => Enum.sort_by(observation.rows, &Serializer.canonical_json/1)
    })
  end

  defp canonicalize_observation(observation, stage) do
    %{observation | observation_sha256: semantic_sha256(observation, stage)}
  end

  # A recorded observation must already carry the digest its own rows imply.
  defp check_recorded_digest(observation, stage) do
    expected = semantic_sha256(observation, stage)

    if observation.observation_sha256 == expected do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_REPLAY,
         stage.contract_id,
         "recorded observation digest does not derive from its rows and stage identity",
         %{recorded: observation.observation_sha256, recomputed: expected}
       )}
    end
  end

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
    |> Enum.sort_by(fn {subject, _} -> Serializer.canonical_json(subject) end)
    |> Enum.flat_map(fn
      {nil, members} -> members
      {_subject, [single]} -> [single]
      {_subject, members} -> [merge_subject(members)]
    end)
  end

  defp row_identity(row) do
    get_in(row, ["_vkg", "row_sha256"]) ||
      Serializer.digest(row)
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
    |> Enum.sort_by(&Serializer.canonical_json/1)
    |> case do
      [single] -> single
      many -> many
    end
  end
end
