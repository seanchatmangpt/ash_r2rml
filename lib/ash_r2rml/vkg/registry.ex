defmodule AshR2RML.VKG.Registry do
  @moduledoc """
  Fail-closed registry for exact VKG source identities.

  Duplicate IDs, duplicate graph identities with different descriptor digests,
  and duplicate source URIs with conflicting source digests are refused rather
  than resolved by last-write-wins behavior.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.Contract

  @type t :: %{required(String.t()) => Contract.t()}

  @spec admit([Contract.t()]) :: {:ok, t()} | {:error, Refusal.t()}
  def admit(contracts) when is_list(contracts) and contracts != [] do
    with {:ok, admitted} <- admit_each(contracts),
         :ok <- unique_ids(admitted),
         :ok <- consistent_sources(admitted),
         :ok <- consistent_graphs(admitted) do
      {:ok, Map.new(admitted, &{&1.id, &1})}
    end
  end

  def admit([]), do: refusal(:contracts, "VKG registry requires at least one contract", %{})
  def admit(other), do: refusal(:contracts, "VKG registry input must be a list", %{value: inspect(other)})

  @spec fetch(t(), String.t()) :: {:ok, Contract.t()} | {:error, Refusal.t()}
  def fetch(registry, id) when is_map(registry) and is_binary(id) do
    case Map.fetch(registry, id) do
      {:ok, contract} -> {:ok, contract}
      :error -> refusal(id, "VKG contract is not admitted in this registry", %{available: registry |> Map.keys() |> Enum.sort()})
    end
  end

  @spec digest(t()) :: String.t()
  def digest(registry) when is_map(registry) do
    registry
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {id, contract} -> {id, Contract.digest(contract)} end)
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp admit_each(contracts) do
    contracts
    |> Enum.reduce_while({:ok, []}, fn contract, {:ok, acc} ->
      case Contract.admit(contract) do
        {:ok, admitted} -> {:cont, {:ok, [admitted | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, admitted} -> {:ok, Enum.reverse(admitted)}
      error -> error
    end
  end

  defp unique_ids(contracts) do
    duplicates =
      contracts
      |> Enum.group_by(& &1.id)
      |> Enum.filter(fn {_id, members} -> length(members) > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicates == [], do: :ok, else: refusal(:ids, "duplicate VKG contract ids are ambiguous", %{duplicates: duplicates})
  end

  defp consistent_sources(contracts) do
    conflicts =
      contracts
      |> Enum.group_by(& &1.source)
      |> Enum.filter(fn {_source, members} -> members |> Enum.map(& &1.source_sha256) |> Enum.uniq() |> length() > 1 end)
      |> Enum.map(&elem(&1, 0))

    if conflicts == [], do: :ok, else: refusal(:sources, "one source URI resolves to multiple admitted descriptor identities", %{conflicts: conflicts})
  end

  defp consistent_graphs(contracts) do
    conflicts =
      contracts
      |> Enum.group_by(& &1.graph)
      |> Enum.filter(fn {_graph, members} -> members |> Enum.map(&Contract.digest/1) |> Enum.uniq() |> length() > 1 end)
      |> Enum.map(&elem(&1, 0))

    if conflicts == [], do: :ok, else: refusal(:graphs, "one graph URI resolves to multiple incompatible contracts", %{conflicts: conflicts})
  end

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_REGISTRY_AMBIGUOUS, subject, detail, evidence)}
  end
end
