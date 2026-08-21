# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ggen do
  @moduledoc """
  ggen-facing deterministic compilation bundle.

  `AshR2RML` does not invoke ggen or write files. It manufactures a path/content
  graph plus an atomic publication plan so ggen can own rendering, filesystem
  actuation, migration versioning, replay, and receipts without independently
  reconstructing semantic decisions.

  Turtle and JSON-LD are alternate RDF input serializations. Both are admitted
  into the same normalized profile before manufacture so ggen never receives a
  serialization-specific semantic fork.

  Cloud ggen may also run in Ash-first mode. In that mode the maintained source
  is the Ash resource graph itself and `compile_ash_ttl_bundle/1` emits the
  ontology, operational SHACL shapes, and R2RML Turtle required by ggen. No
  checked-in ontology/profile TTL is required for that path.
  """

  alias AshR2RML.{Compilation, Manufacturing}

  @spec compile_bundle(map()) :: {:ok, map()} | {:error, Compilation.t() | term()}
  def compile_bundle(profile) do
    with {:ok, dfcm} <- AshR2RML.DfCM.Compiler.compile(profile),
         compilation = dfcm.compilation,
         {:ok, receipt_json} <- encode_json(compilation.receipt),
         {:ok, integrity_json} <- encode_json(dfcm.integrity_receipt),
         {:ok, catalog_json} <- encode_json(compilation.ir) do
      files = %{
        "generated/ash/ontology_resources.ex" => compilation.ash_source,
        "generated/ecto/semantic_schema_migration.exs" => compilation.ecto_migration,
        "generated/sql/semantic_schema.sql" => compilation.postgres_ddl,
        "priv/r2rml/mapping.ttl" => compilation.r2rml,
        "generated/shacl/operational-profile.ttl" => compilation.shacl,
        "generated/catalog/resource-map.json" => catalog_json,
        "receipts/semantic-compilation.json" => receipt_json,
        "receipts/semantic-integrity.json" => integrity_json
      }

      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         receipt: compilation.receipt,
         integrity_receipt: dfcm.integrity_receipt,
         session_identity: dfcm.session_identity,
         proof_classes: dfcm.proof_classes,
         manufacturing_plan: Manufacturing.plan(files, dfcm.session_identity),
         files: files
       }}
    end
  end

  @doc "Verify hashes reported by ggen for an isolated stage before atomic publication."
  @spec verify_staged(map(), map()) ::
          {:ok, AshR2RML.Manufacturing.VerificationReceipt.t()} | {:error, AshR2RML.Refusal.t()}
  def verify_staged(%{manufacturing_plan: %AshR2RML.Manufacturing.Plan{} = plan}, observed_hashes)
      when is_map(observed_hashes) do
    Manufacturing.verify_staged(plan, observed_hashes)
  end

  @doc "Manufacture cloud-ggen TTL inputs directly from one or more Ash resources."
  @spec compile_ash_ttl_bundle(module() | [module()] | AshR2RML.Mapping.Bundle.t()) ::
          {:ok, map()} | {:error, term()}
  defdelegate compile_ash_ttl_bundle(resources_or_bundle), to: AshR2RML.Ggen.TTL, as: :emit

  @doc "Parse an RDF/SHACL Turtle profile, then manufacture the same deterministic ggen bundle."
  @spec compile_turtle_bundle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_turtle_bundle(turtle, opts \\ []) do
    with :ok <- AshR2RML.Bounds.admit_input(turtle, opts),
         {:ok, profile} <- AshR2RML.Ingestion.from_turtle(turtle, opts) do
      compile_bundle(profile)
    end
  end

  @doc "Parse a JSON-LD 1.1 RDF/SHACL profile, then manufacture the same deterministic ggen bundle."
  @spec compile_jsonld_bundle(String.t() | map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_jsonld_bundle(jsonld, opts \\ []) do
    with :ok <- AshR2RML.Bounds.admit_input(jsonld, opts),
         {:ok, profile} <- AshR2RML.JSONLD.ingest(jsonld, opts) do
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