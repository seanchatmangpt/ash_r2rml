defmodule AshR2RML.VKG.Provenance do
  @moduledoc """
  Adds exact source/contract/query provenance to observed VKG rows.
  """

  alias AshR2RML.VKG.QueryPlan

  @spec attach(map(), QueryPlan.stage(), map()) :: map()
  def attach(row, stage, observation) when is_map(row) do
    subject = subject(row)

    Map.put(row, "_vkg", %{
      "contract_id" => stage.contract_id,
      "source" => stage.source,
      "graph" => stage.graph,
      "source_sha256" => stage.source_sha256,
      "mapping_sha256" => stage.mapping_sha256,
      "query_sha256" => stage.query_sha256,
      "observation_sha256" => Map.get(observation, :observation_sha256),
      "subject" => subject,
      "row_sha256" => row_hash(stage.contract_id, subject, row)
    })
  end

  @spec exact_source?(map(), QueryPlan.stage()) :: boolean()
  def exact_source?(row, stage) when is_map(row) do
    meta = Map.get(row, "_vkg", %{})

    meta["contract_id"] == stage.contract_id and
      meta["source_sha256"] == stage.source_sha256 and
      meta["mapping_sha256"] == stage.mapping_sha256 and
      meta["query_sha256"] == stage.query_sha256
  end

  @spec strip(map()) :: map()
  def strip(row) when is_map(row), do: Map.delete(row, "_vkg")

  defp subject(row) do
    Map.get(row, "subject") ||
      Map.get(row, "s") ||
      Map.get(row, :subject) ||
      Map.get(row, :s)
  end

  defp row_hash(contract_id, subject, row) do
    AshR2RML.VKG.Serializer.digest(%{
      "kind" => "vkg.row",
      "contract_id" => contract_id,
      "subject" => subject,
      "row" => row |> Map.delete("_vkg") |> Map.delete(:_vkg)
    })
  end
end
