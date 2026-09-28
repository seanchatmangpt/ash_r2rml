defmodule AshR2RML.VKG.Compatibility do
  @moduledoc "Fail-closed compatibility court for composing VKG contracts."
  alias AshR2RML.Refusal
  alias AshR2RML.VKG.Contract

  def check(contracts) when is_list(contracts) and contracts != [] do
    with :ok <- versions(contracts), :ok <- unique_graphs(contracts), :ok <- observe_only(contracts), do: :ok
  end
  def check(other), do: refusal(:contracts,"compatibility requires a non-empty contract list",%{value: inspect(other)})

  def matrix(contracts) do
    for left <- contracts, right <- contracts, left.id <= right.id do
      %{left: left.id, right: right.id, same_version?: left.version == right.version,
        graph_collision?: left.graph == right.graph and left.id != right.id,
        source_collision?: left.source == right.source and left.source_sha256 != right.source_sha256,
        compatible?: compatible_pair?(left,right)}
    end
  end

  defp versions(contracts) do
    versions=contracts |> Enum.map(& &1.version) |> Enum.uniq()
    if length(versions)==1, do: :ok, else: refusal(:version,"VKG contracts must share one admitted version",%{versions: versions})
  end
  defp unique_graphs(contracts) do
    collisions=contracts |> Enum.group_by(& &1.graph) |> Enum.filter(fn {_g,m}->m |> Enum.map(& &1.id) |> Enum.uniq() |> length()>1 end) |> Enum.map(&elem(&1,0))
    if collisions==[], do: :ok, else: refusal(:graph,"VKG graph identities collide",%{graphs: collisions})
  end
  defp observe_only(contracts) do
    elevated=Enum.filter(contracts,&(&1.authority != :NONE))
    if elevated==[], do: :ok, else: refusal(:authority,"VKG refuses actuation authority",%{contracts: Enum.map(elevated,& &1.id)})
  end
  defp compatible_pair?(%Contract{}=l,%Contract{}=r), do: l.version==r.version and not(l.graph==r.graph and l.id!=r.id) and l.authority==:NONE and r.authority==:NONE
  defp refusal(subject,detail,evidence), do: {:error,Refusal.new(:REFUSED_VKG_COMPATIBILITY,subject,detail,evidence)}
end
