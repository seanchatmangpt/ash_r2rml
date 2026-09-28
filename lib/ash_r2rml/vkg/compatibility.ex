defmodule AshR2RML.VKG.Compatibility do
  @moduledoc """
  Fail-closed compatibility court for composing VKG contracts.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.Contract

  @spec check([Contract.t()]) :: :ok | {:error, Refusal.t()}
  def check(contracts) when is_list(contracts) and contracts != [] do
    with :ok <- versions(contracts),
         :ok <- unique_graphs(contracts),
         :ok <- observe_only(contracts) do
      :ok
    end
  end

  def check(other) do
    refusal(
      :contracts,
      "compatibility requires a non-empty contract list",
      %{value: inspect(other)}
    )
  end

  @spec matrix([Contract.t()]) :: [map()]
  def matrix(contracts) do
    for left <- contracts,
        right <- contracts,
        left.id <= right.id do
      %{
        left: left.id,
        right: right.id,
        same_version?: left.version == right.version,
        graph_collision?: left.graph == right.graph and left.id != right.id,
        source_collision?:
          left.source == right.source and
            left.source_sha256 != right.source_sha256,
        compatible?: compatible_pair?(left, right)
      }
    end
  end

  defp versions(contracts) do
    versions = contracts |> Enum.map(& &1.version) |> Enum.uniq()

    if length(versions) == 1 do
      :ok
    else
      refusal(
        :version,
        "VKG contracts must share one admitted version",
        %{versions: versions}
      )
    end
  end

  defp unique_graphs(contracts) do
    collisions =
      contracts
      |> Enum.group_by(& &1.graph)
      |> Enum.filter(fn {_graph, members} ->
        members
        |> Enum.map(& &1.id)
        |> Enum.uniq()
        |> length() > 1
      end)
      |> Enum.map(&elem(&1, 0))

    if collisions == [] do
      :ok
    else
      refusal(
        :graph,
        "VKG graph identities collide",
        %{graphs: collisions}
      )
    end
  end

  defp observe_only(contracts) do
    elevated = Enum.filter(contracts, &(&1.authority != :NONE))

    if elevated == [] do
      :ok
    else
      refusal(
        :authority,
        "VKG refuses actuation authority",
        %{contracts: Enum.map(elevated, & &1.id)}
      )
    end
  end

  defp compatible_pair?(%Contract{} = left, %Contract{} = right) do
    left.version == right.version and
      not (left.graph == right.graph and left.id != right.id) and
      left.authority == :NONE and
      right.authority == :NONE
  end

  defp refusal(subject, detail, evidence) do
    {:error, Refusal.new(:REFUSED_VKG_COMPATIBILITY, subject, detail, evidence)}
  end
end
