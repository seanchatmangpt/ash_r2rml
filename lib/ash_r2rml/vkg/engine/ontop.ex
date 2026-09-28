defmodule AshR2RML.VKG.Engine.Ontop do
  @moduledoc """
  Observe-only VKG execution adapter over AshR2RML.OBDA.Ontop.

  A caller may inject a three-arity runner for deterministic tests. Injected
  execution retains AshR2RML's existing test-double standing and is never
  promoted to a live-observation claim.
  """

  alias AshR2RML.OBDA.Ontop

  @spec execute(map(), keyword()) ::
          {:ok, AshR2RML.OBDA.Observation.t()} | {:error, AshR2RML.OBDA.Observation.t()}
  def execute(stage, opts \\ []) when is_map(stage) do
    query_opts =
      [
        mapping_path: stage.mapping_path,
        query_path: stage.query_path,
        ontology_path: stage.ontology_path,
        engine_version: Keyword.get(opts, :engine_version, "5.5"),
        timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
        max_rows: Keyword.get(opts, :max_rows, 50_000),
        max_output_bytes: Keyword.get(opts, :max_output_bytes, 4 * 1024 * 1024),
        retain_raw_output: Keyword.get(opts, :retain_raw_output, false),
        required_capabilities: Keyword.get(opts, :required_capabilities, [])
      ]
      |> maybe_put(:properties_path, Keyword.get(opts, :properties_path))
      |> maybe_put(:db_url, Keyword.get(opts, :db_url))
      |> maybe_put(:db_user, Keyword.get(opts, :db_user))
      |> maybe_put(:db_password, Keyword.get(opts, :db_password))
      |> maybe_put(:db_driver, Keyword.get(opts, :db_driver))
      |> maybe_put(:binary, Keyword.get(opts, :binary))
      |> maybe_put(:prefix_args, Keyword.get(opts, :prefix_args))

    case Keyword.get(opts, :runner) do
      runner when is_function(runner, 3) -> Ontop.query(query_opts, runner)
      _ -> Ontop.query(query_opts)
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
