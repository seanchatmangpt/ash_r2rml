defmodule AshR2RML.VKG.Registry do
  @moduledoc "Fail-closed registry for exact VKG source identities."
  alias AshR2RML.VKG.Contract
  def admit(contracts) when is_list(contracts) do
    with true <- Enum.all?(contracts, &match?({:ok,_}, Contract.admit(&1))),
         ids when length(ids)==length(Enum.uniq(ids)) <- Enum.map(contracts,& &1.id),
         sources when length(sources)==length(Enum.uniq(sources)) <- Enum.map(contracts,&{&1.source,&1.source_sha256}) do
      {:ok, Map.new(contracts,&{&1.id,&1})}
    else _ -> {:error,:REFUSED_VKG_REGISTRY_AMBIGUOUS} end
  end
  def admit(_), do: {:error,:REFUSED_VKG_REGISTRY_SHAPE}
end
