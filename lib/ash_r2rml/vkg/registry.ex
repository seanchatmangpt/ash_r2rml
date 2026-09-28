defmodule AshR2RML.VKG.Registry do
  @moduledoc "Exact-view registry; duplicate semantic view identities fail closed."
  alias AshR2RML.VKG.Contract
  def new, do: %{}
  def put(registry, %Contract{view: view}=contract) do
    with {:ok, admitted} <- Contract.admit(contract), false <- Map.has_key?(registry, view) do {:ok, Map.put(registry, view, admitted)} else true -> {:error, :refused_duplicate_view}; {:error, _}=e -> e end
  end
  def fetch(registry, view), do: Map.fetch(registry, view)
end
