# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.Ggen do
  @moduledoc """
  ggen-facing deterministic compilation bundle.

  `AshR2ml` does not invoke ggen or write files. It manufactures a path/content
  graph so ggen can own rendering, filesystem actuation, migration versioning,
  replay, and receipts without independently reconstructing semantic decisions.
  """

  alias AshR2ml.Compilation

  @spec compile_bundle(map()) :: {:ok, map()} | {:error, Compilation.t() | term()}
  def compile_bundle(profile) do
    with {:ok, compilation} <- AshR2ml.Compiler.compile(profile),
         {:ok, receipt_json} <- encode_json(compilation.receipt),
         {:ok, catalog_json} <- encode_json(compilation.ir) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         receipt: compilation.receipt,
         files: %{
           "generated/ash/ontology_resources.ex" => compilation.ash_source,
           "generated/ecto/semantic_schema_migration.exs" => compilation.ecto_migration,
           "generated/sql/semantic_schema.sql" => compilation.postgres_ddl,
           "priv/r2rml/mapping.ttl" => compilation.r2rml,
           "generated/shacl/operational-profile.ttl" => compilation.shacl,
           "generated/catalog/resource-map.json" => catalog_json,
           "receipts/semantic-compilation.json" => receipt_json
         }
       }}
    end
  end

  @doc "Parse an RDF/SHACL Turtle profile, then manufacture the same deterministic ggen bundle."
  @spec compile_turtle_bundle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_turtle_bundle(turtle, opts \\ []) do
    with {:ok, profile} <- AshR2ml.Ingestion.from_turtle(turtle, opts) do
      compile_bundle(profile)
    end
  end

  defp encode_json(value) do
    value
    |> json_term()
    |> Jason.encode(pretty: true)
  end

  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()

  defp json_term(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_term(value)} end)
  end

  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&json_term/1)
  defp json_term(value) when value in [true, false, nil], do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value) when is_binary(value) or is_number(value), do: value
  defp json_term(value), do: inspect(value)

  defp json_key({class_iri, relationship}), do: class_iri <> "#" <> to_string(relationship)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: inspect(key)
end
