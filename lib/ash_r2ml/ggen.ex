# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Ggen do
  @moduledoc """
  ggen-facing deterministic compilation bundle.

  `AshR2ml` does not invoke ggen or write files. It manufactures a path/content
  graph so ggen can own rendering, filesystem actuation, replay, and receipts
  without having to independently reconstruct semantic decisions.
  """

  alias AshR2ml.Compilation

  @spec compile_bundle(map()) :: {:ok, map()} | {:error, Compilation.t() | term()}
  def compile_bundle(profile) do
    with {:ok, compilation} <- AshR2ml.Compiler.compile(profile),
         {:ok, receipt_json} <- receipt_json(compilation) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         receipt: compilation.receipt,
         files: %{
           "generated/ash/ontology_resources.ex" => compilation.ash_source,
           "generated/sql/semantic_schema.sql" => compilation.postgres_ddl,
           "priv/r2rml/xaas.ttl" => compilation.r2rml,
           "generated/shacl/operational-profile.ttl" => compilation.shacl,
           "receipts/semantic-compilation.json" => receipt_json
         }
       }}
    end
  end

  defp receipt_json(%Compilation{receipt: receipt}) do
    receipt
    |> Map.from_struct()
    |> stringify_storage_maps()
    |> Jason.encode(pretty: true)
  end

  defp stringify_storage_maps(receipt) do
    receipt
    |> Map.update(:storage_candidates, %{}, &stringify_relation_map/1)
    |> Map.update(:selected_storage, %{}, &stringify_relation_map/1)
    |> Map.update(:refusals, [], fn refusals -> Enum.map(refusals, &Map.from_struct/1) end)
  end

  defp stringify_relation_map(map) do
    Map.new(map, fn
      {{class_iri, relationship}, value} -> {class_iri <> "#" <> to_string(relationship), value}
      {key, value} -> {to_string(key), value}
    end)
  end
end
