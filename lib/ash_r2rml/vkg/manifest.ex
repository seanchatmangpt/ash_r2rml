defmodule AshR2RML.VKG.Manifest do
  @moduledoc """
  Loader for canonical VKG source descriptors under priv/vkg/sources.

  Digests are manufactured from the descriptor and exact mapping/query bytes at
  load time. This prevents a stale hand-copied digest from becoming an alternate
  semantic root.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Contract, SourceIdentity}

  @default_root Path.expand("../../../priv/vkg", __DIR__)

  @spec default_root() :: String.t()
  def default_root, do: @default_root

  @spec load_all(String.t()) :: {:ok, [Contract.t()]} | {:error, Refusal.t()}
  def load_all(root \\ @default_root) do
    source_dir = Path.join(root, "sources")

    source_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case load(path, root) do
        {:ok, contract} -> {:cont, {:ok, [contract | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, contracts} when contracts != [] -> {:ok, Enum.reverse(contracts)}
      {:ok, []} -> refusal(:sources, "no VKG source manifests found", %{root: root})
      {:error, _} = error -> error
    end
  end

  @spec load(String.t(), String.t()) :: {:ok, Contract.t()} | {:error, Refusal.t()}
  def load(path, root \\ @default_root) do
    with {:ok, bytes} <- read(path, :source_manifest),
         {:ok, attrs} <- decode(bytes, path),
         {:ok, source_identity} <-
           SourceIdentity.new(%{
             id: attrs["id"],
             uri: attrs["source"],
             graph: attrs["graph"],
             subject_template: attrs["subject_template"],
             version: attrs["version"] || "1"
           }),
         {:ok, mapping_path} <- resolve(root, attrs["mapping"], :mapping),
         {:ok, query_path} <- resolve(root, attrs["query"], :query),
         {:ok, mapping} <- read(mapping_path, :mapping),
         {:ok, query} <- read(query_path, :query),
         {:ok, ontology_path} <- optional_resolve(root, attrs["ontology"]) do
      contract = %Contract{
        id: source_identity.id,
        source: source_identity.uri,
        graph: source_identity.graph,
        subject_template: source_identity.subject_template,
        source_sha256: source_identity.sha256,
        mapping_sha256: sha256(mapping),
        query_sha256: sha256(query),
        mapping_path: mapping_path,
        query_path: query_path,
        ontology_path: ontology_path,
        version: attrs["version"] || "1",
        capabilities: normalize_capabilities(attrs["capabilities"]),
        authority: :NONE,
        standing: :constructed_not_actuated
      }

      Contract.admit(contract)
    end
  end

  @spec snapshot(Contract.t()) :: map()
  def snapshot(%Contract{} = contract) do
    %{
      id: contract.id,
      source: contract.source,
      graph: contract.graph,
      source_sha256: contract.source_sha256,
      mapping_sha256: contract.mapping_sha256,
      query_sha256: contract.query_sha256,
      subject_template: contract.subject_template,
      version: contract.version,
      capabilities: contract.capabilities
    }
  end

  defp resolve(root, rel, kind) when is_binary(rel) do
    path = Path.expand(rel, root)
    root = Path.expand(root)

    cond do
      not String.starts_with?(path, root <> "/") ->
        refusal(kind, "VKG manifest path escapes its admitted root", %{path: rel})

      File.regular?(path) ->
        {:ok, path}

      true ->
        refusal(kind, "VKG manifest references a missing file", %{path: path})
    end
  end

  defp resolve(_root, value, kind) do
    refusal(kind, "VKG manifest path must be a string", %{value: inspect(value)})
  end

  defp optional_resolve(_root, nil), do: {:ok, nil}
  defp optional_resolve(root, rel), do: resolve(root, rel, :ontology)

  defp read(path, kind) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> refusal(kind, "unable to read VKG artifact", %{path: path, reason: reason})
    end
  end

  defp decode(bytes, path) do
    case Jason.decode(bytes) do
      {:ok, attrs} when is_map(attrs) ->
        {:ok, attrs}

      {:ok, other} ->
        refusal(:source_manifest, "VKG manifest must decode to an object", %{
          path: path,
          value: inspect(other)
        })

      {:error, error} ->
        refusal(:source_manifest, "VKG manifest JSON is invalid", %{
          path: path,
          error: Exception.message(error)
        })
    end
  end

  defp normalize_capabilities(nil), do: [:select]

  defp normalize_capabilities(values) when is_list(values) do
    values
    |> Enum.map(fn
      "select" -> :select
      "aggregate" -> :aggregate
      "join" -> :join
      "filter" -> :filter
      other when is_binary(other) -> {:extension, other}
      other -> {:invalid, other}
    end)
  end

  defp normalize_capabilities(_), do: [:select]

  defp sha256(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_MANIFEST, subject, detail, evidence)}
  end
end
