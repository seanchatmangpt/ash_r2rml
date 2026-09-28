defmodule AshR2RML.VKG.Planner do
  @moduledoc """
  Plans a federated query from exact admitted contracts without executing it.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Catalog, Contract, QueryPlan}

  @spec plan(Catalog.t(), [String.t()], keyword()) ::
          {:ok, QueryPlan.t()} | {:error, Refusal.t()}
  def plan(%Catalog{} = catalog, contract_ids, opts \\ []) do
    with {:ok, contracts} <- Catalog.select(catalog, contract_ids),
         :ok <- ensure_capability(contracts, Keyword.get(opts, :capability, :select)),
         stages <- Enum.map(contracts, &stage/1),
         {:ok, plan} <- QueryPlan.new(catalog.sha256, contract_ids, stages, opts) do
      {:ok, plan}
    end
  end

  @spec plan_all(Catalog.t(), keyword()) :: {:ok, QueryPlan.t()} | {:error, Refusal.t()}
  def plan_all(%Catalog{} = catalog, opts \\ []) do
    plan(catalog, Catalog.ids(catalog), opts)
  end

  defp stage(%Contract{} = contract) do
    %{
      contract_id: contract.id,
      source: contract.source,
      graph: contract.graph,
      source_sha256: contract.source_sha256,
      mapping_sha256: contract.mapping_sha256,
      query_sha256: contract.query_sha256,
      mapping_path: contract.mapping_path,
      query_path: contract.query_path,
      ontology_path: contract.ontology_path,
      subject_template: contract.subject_template,
      version: contract.version
    }
  end

  defp ensure_capability(contracts, capability) do
    missing =
      contracts
      |> Enum.reject(&supports?(&1, capability))
      |> Enum.map(& &1.id)

    if missing == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_CAPABILITY,
         capability,
         "one or more VKG contracts do not admit the required capability",
         %{missing_contracts: missing}
       )}
    end
  end

  defp supports?(%Contract{capabilities: capabilities}, capability) do
    capability in capabilities or {:extension, Atom.to_string(capability)} in capabilities
  end
end
