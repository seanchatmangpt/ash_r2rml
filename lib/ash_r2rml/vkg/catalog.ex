defmodule AshR2RML.VKG.Catalog do
  @moduledoc """
  Immutable admitted catalog of VKG contracts.

  The catalog is the transition from source manifests to query planning. Its
  digest is carried into every plan and receipt, preventing replay against a
  silently different source registry.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Contract, Manifest, Registry}

  @enforce_keys [:contracts, :sha256]
  defstruct [:contracts, :sha256]

  @type t :: %__MODULE__{contracts: Registry.t(), sha256: String.t()}

  @spec load(String.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def load(root \\ Manifest.default_root()) do
    with {:ok, contracts} <- Manifest.load_all(root),
         {:ok, registry} <- Registry.admit(contracts) do
      {:ok, %__MODULE__{contracts: registry, sha256: Registry.digest(registry)}}
    end
  end

  @spec new([Contract.t()]) :: {:ok, t()} | {:error, Refusal.t()}
  def new(contracts) do
    with {:ok, registry} <- Registry.admit(contracts) do
      {:ok, %__MODULE__{contracts: registry, sha256: Registry.digest(registry)}}
    end
  end

  @spec fetch(t(), String.t()) :: {:ok, Contract.t()} | {:error, Refusal.t()}
  def fetch(%__MODULE__{contracts: registry}, id), do: Registry.fetch(registry, id)

  @spec select(t(), [String.t()]) :: {:ok, [Contract.t()]} | {:error, Refusal.t()}
  def select(%__MODULE__{} = catalog, ids) when is_list(ids) and ids != [] do
    ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn id, {:ok, acc} ->
      case fetch(catalog, id) do
        {:ok, contract} -> {:cont, {:ok, [contract | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, contracts} -> {:ok, Enum.reverse(contracts)}
      error -> error
    end
  end

  def select(_catalog, ids) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_QUERY_SCOPE,
       :contracts,
       "VKG query must select at least one admitted contract",
       %{ids: inspect(ids)}
     )}
  end

  @spec ids(t()) :: [String.t()]
  def ids(%__MODULE__{contracts: contracts}), do: contracts |> Map.keys() |> Enum.sort()

  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{} = catalog) do
    %{
      catalog_sha256: catalog.sha256,
      contracts:
        catalog.contracts
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {_id, contract} -> Contract.identity(contract) end)
    }
  end
end
