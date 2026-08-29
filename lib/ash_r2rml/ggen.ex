# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ggen do
  @moduledoc """
  ggen-facing deterministic compilation bundle.

  `AshR2RML` does not invoke ggen or write files. It manufactures a path/content
  graph so ggen can own rendering, filesystem actuation, migration versioning,
  replay, and receipts without independently reconstructing semantic decisions.

  Turtle and JSON-LD are alternate RDF input serializations. Both are admitted
  into the same normalized profile before manufacture so ggen never receives a
  serialization-specific semantic fork.

  Cloud ggen may also run in Ash-first mode. In that mode the maintained source
  is the Ash resource graph itself and `compile_ash_ttl_bundle/1` emits the
  ontology, operational SHACL shapes, and R2RML Turtle required by ggen.

  Semantic types use the same boundary: `compile_semantic_types_bundle/2`
  admits a content-addressed plan and returns deterministic generated artifacts.
  Runtime integration uses `compile_runtime_contract/1` to manufacture the exact-subject,
  authority-bound input consumed by the marketplace runtime integration pack.
  ggen still owns DO.
  """

  alias AshR2RML.{Compilation, Refusal}

  @spec compile_bundle(map()) :: {:ok, map()} | {:error, Compilation.t() | term()}
  def compile_bundle(profile) do
    with {:ok, compilation} <- AshR2RML.Compiler.compile(profile),
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

  @doc "Manufacture a deterministic ggen path/content graph from a semantic type profile."
  @spec compile_semantic_types_bundle(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_semantic_types_bundle(source, opts \\ []) do
    with {:ok, plan} <- AshR2RML.SemanticTypes.plan(source, opts),
         {:ok, files} <- AshR2RML.SemanticTypes.Generator.files(plan, opts),
         {:ok, receipt_json} <-
           encode_json(%{
             plan_id: plan.id,
             standing: :construct_only,
             status: :PARTIAL_ALIVE,
             providers: plan.providers,
             type_ids: Enum.map(plan.types, & &1.id)
           }) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         semantic_type_plan_id: plan.id,
         plan: plan,
         files: Map.put(files, "receipts/semantic-type-compilation.json", receipt_json <> "\n")
       }}
    end
  end

  @doc "Manufacture cloud-ggen TTL inputs directly from one or more Ash resources."
  @spec compile_ash_ttl_bundle(module() | [module()] | AshR2RML.Mapping.Bundle.t()) :: {:ok, map()} | {:error, term()}
  defdelegate compile_ash_ttl_bundle(resources_or_bundle), to: AshR2RML.Ggen.TTL, as: :emit

  @doc "Manufacture an exact-subject runtime integration contract for the GGen marketplace pack."
  @spec compile_runtime_contract(map()) :: {:ok, map()} | {:error, atom()}
  defdelegate compile_runtime_contract(input), to: AshR2RML.GgenRuntime, as: :contract

  @doc "Parse an RDF/SHACL Turtle profile, then manufacture the same deterministic ggen bundle."
  @spec compile_turtle_bundle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_turtle_bundle(turtle, opts \\ []) do
    with {:ok, profile} <- AshR2RML.Ingestion.from_turtle(turtle, opts), do: compile_bundle(profile)
  end

  @doc "Parse a JSON-LD 1.1 RDF/SHACL profile, then manufacture the same deterministic ggen bundle."
  @spec compile_jsonld_bundle(String.t() | map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_jsonld_bundle(jsonld, opts \\ []) do
    with {:ok, profile} <- AshR2RML.JSONLD.ingest(jsonld, opts), do: compile_bundle(profile)
  end

  @doc """
  Manufacture a deterministic ggen bundle containing only Ash resource source with
  auto-derived `graphql do ... end`/`json_api do ... end` blocks, from the same admitted
  mapping IR `compile_bundle/1` uses -- additive, does not change `compile_bundle/1`'s output.

  This does not add a GraphQL/JSON:API runtime dependency to `AshR2RML` itself: any consumer
  resource can already add `AshGraphql.Resource`/`AshJsonApi.Resource` directly, independent of
  AshR2RML, because Ash extensions compose. `opts` is `graphql: true` and/or `json_api: true`
  (both default `false`); see `AshR2RML.Semantic.Ash.render/2` for exactly what's derived.
  """
  @spec compile_api_bundle(map(), keyword()) :: {:ok, map()} | {:error, [Refusal.t()]}
  def compile_api_bundle(profile, opts \\ []) when is_map(profile) do
    with {:ok, ir} <- AshR2RML.Admission.admit(profile),
         {:ok, ash_source} <- AshR2RML.Semantic.Ash.render(ir, opts) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         files: %{"generated/ash/api_resources.ex" => ash_source}
       }}
    end
  end

  defp encode_json(value), do: value |> json_term() |> Jason.encode(pretty: true)
  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()
  defp json_term(map) when is_map(map), do: Map.new(map, fn {key, value} -> {json_key(key), json_term(value)} end)
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
