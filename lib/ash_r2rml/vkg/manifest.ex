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
  def load_all(root \\ @default_root)

  def load_all(root) when is_binary(root) and root != "" do
    source_dir = Path.join(root, "sources")

    case File.ls(source_dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.map(&Path.join(source_dir, &1))
        |> load_paths(root)

      {:error, _reason} ->
        refusal(:sources, "no VKG source manifests found", %{root: root})
    end
  end

  def load_all(other),
    do: refusal(:root, "VKG manifest root must be a non-empty string", %{value: inspect(other)})

  defp load_paths(paths, root) do
    paths
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
  def load(path, root \\ @default_root)

  def load(path, root) when is_binary(path) and path != "" and is_binary(root) and root != "" do
    with {:ok, manifest_path} <- contained(root, path, "sources", :source_manifest),
         {:ok, bytes} <- read(manifest_path, :source_manifest),
         {:ok, attrs} <- decode(bytes, path),
         {:ok, version} <- version(attrs["version"]),
         {:ok, capabilities} <- capabilities(attrs["capabilities"]),
         {:ok, source_identity} <-
           SourceIdentity.new(%{
             id: attrs["id"],
             uri: attrs["source"],
             graph: attrs["graph"],
             subject_template: attrs["subject_template"],
             version: version
           }),
         {:ok, mapping_path} <- resolve(root, attrs["mapping"], :mapping),
         {:ok, query_path} <- resolve(root, attrs["query"], :query),
         {:ok, mapping} <- read(mapping_path, :mapping),
         {:ok, query} <- read(query_path, :query),
         {:ok, ontology_path} <- optional_resolve(root, attrs["ontology"]),
         {:ok, ontology_sha256} <- optional_digest(ontology_path) do
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
        ontology_sha256: ontology_sha256,
        version: version,
        capabilities: capabilities,
        authority: :NONE,
        standing: :constructed_not_actuated
      }

      Contract.admit(contract)
    end
  end

  def load(path, root),
    do:
      refusal(:source_manifest, "VKG manifest path and root must be non-empty strings", %{
        path: inspect(path),
        root: inspect(root)
      })

  @spec snapshot(Contract.t()) :: map()
  def snapshot(%Contract{} = contract) do
    %{
      id: contract.id,
      source: contract.source,
      graph: contract.graph,
      source_sha256: contract.source_sha256,
      mapping_sha256: contract.mapping_sha256,
      query_sha256: contract.query_sha256,
      ontology_sha256: contract.ontology_sha256,
      subject_template: contract.subject_template,
      version: contract.version,
      capabilities: contract.capabilities
    }
  end

  defp resolve(root, rel, kind) when is_binary(rel) and rel != "" do
    contained(root, rel, nil, kind)
  end

  defp resolve(_root, value, kind) do
    refusal(kind, "VKG manifest path must be a string", %{value: inspect(value)})
  end

  # Resolves `rel` against `root`, refusing lexical escapes, symlinked path
  # components below the root, and missing or non-regular files. `subdir`
  # (when given) narrows the admitted area beneath the root.
  defp contained(root, rel, subdir, kind) do
    root = Path.expand(root)
    base = if subdir, do: Path.join(root, subdir), else: root
    path = Path.expand(rel, root)

    cond do
      not String.starts_with?(path, base <> "/") ->
        refusal(kind, "VKG manifest path escapes its admitted root", %{path: rel})

      symlinked?(root, path) ->
        refusal(kind, "VKG manifest path traverses a symlink", %{path: rel})

      File.regular?(path) ->
        {:ok, path}

      true ->
        refusal(kind, "VKG manifest references a missing file", %{path: path})
    end
  end

  defp symlinked?(root, path) do
    path
    |> Path.relative_to(root)
    |> Path.split()
    |> Enum.reduce_while(root, fn part, acc ->
      next = Path.join(acc, part)

      case File.lstat(next) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, :symlink}
        _ -> {:cont, next}
      end
    end)
    |> Kernel.==(:symlink)
  end

  defp optional_digest(nil), do: {:ok, nil}

  defp optional_digest(path) do
    with {:ok, bytes} <- read(path, :ontology), do: {:ok, sha256(bytes)}
  end

  defp version(nil), do: {:ok, "1"}
  defp version(v) when is_binary(v) and v != "", do: {:ok, v}

  defp version(other),
    do: refusal(:version, "VKG manifest version must be a non-empty string", %{value: inspect(other)})

  defp capabilities(nil), do: {:ok, [:select]}

  defp capabilities(values) when is_list(values) and values != [] do
    allowed = Map.new(Contract.capability_allowlist(), &{Atom.to_string(&1), &1})

    invalid = Enum.reject(values, &(is_binary(&1) and Map.has_key?(allowed, &1)))

    if invalid == [] do
      {:ok, values |> Enum.map(&Map.fetch!(allowed, &1)) |> Enum.uniq() |> Enum.sort()}
    else
      capability_refusal(%{invalid: Enum.map(invalid, &inspect/1)})
    end
  end

  defp capabilities(other), do: capability_refusal(%{value: inspect(other)})

  defp capability_refusal(evidence) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_CAPABILITY,
       :capabilities,
       "VKG manifest capabilities must be a non-empty list drawn from the observe-only allowlist",
       Map.put(evidence, :allowed, Contract.capability_allowlist())
     )}
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

  defp sha256(bytes) do
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_MANIFEST, subject, detail, evidence)}
  end
end
