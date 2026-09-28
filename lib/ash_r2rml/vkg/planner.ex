defmodule AshR2RML.VKG.Planner do
  @moduledoc """
  Plans a federated query from exact admitted contracts without executing it.

  Planning is fail-closed: the selection must pass the Compatibility court, the
  requested capability must belong to the closed observe-only allowlist and be
  admitted by every selected contract, and each stage is bound to its contract
  digest so a plan cannot be detached from the catalog that admitted it.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.{Catalog, Compatibility, Contract, QueryPlan}

  @spec plan(Catalog.t(), [String.t()], keyword()) ::
          {:ok, QueryPlan.t()} | {:error, Refusal.t()}
  def plan(catalog, contract_ids, opts \\ [])

  def plan(%Catalog{} = catalog, contract_ids, opts) when is_list(opts) do
    capability = Keyword.get(opts, :capability, :select)

    with :ok <- valid_capability(capability),
         {:ok, contracts} <- Catalog.select(catalog, contract_ids),
         :ok <- Compatibility.check(contracts),
         :ok <- ensure_capability(contracts, capability),
         stages <- Enum.map(contracts, &stage/1) do
      QueryPlan.new(catalog.sha256, contract_ids, stages, opts)
    end
  end

  def plan(%Catalog{}, _contract_ids, opts), do: options_refusal(opts)

  def plan(other, _contract_ids, _opts) do
    {:error,
     Refusal.new(
       :REFUSED_VKG_QUERY_SCOPE,
       :catalog,
       "VKG planning requires an admitted catalog",
       %{value: inspect(other)}
     )}
  end

  @spec plan_all(Catalog.t(), keyword()) :: {:ok, QueryPlan.t()} | {:error, Refusal.t()}
  def plan_all(%Catalog{} = catalog, opts \\ []) do
    plan(catalog, Catalog.ids(catalog), opts)
  end

  defp options_refusal(opts) do
    {:error,
     Refusal.new(:REFUSED_VKG_QUERY_PLAN, :options, "VKG plan options must be a keyword list", %{
       value: inspect(opts)
     })}
  end

  defp stage(%Contract{} = contract) do
    %{
      contract_id: contract.id,
      contract_digest: Contract.digest(contract),
      source: contract.source,
      graph: contract.graph,
      source_sha256: contract.source_sha256,
      mapping_sha256: contract.mapping_sha256,
      query_sha256: contract.query_sha256,
      ontology_sha256: contract.ontology_sha256,
      mapping_path: contract.mapping_path,
      query_path: contract.query_path,
      ontology_path: contract.ontology_path,
      subject_template: contract.subject_template,
      version: contract.version,
      capabilities: Enum.sort(contract.capabilities)
    }
  end

  defp valid_capability(capability) do
    if capability in Contract.capability_allowlist() do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_VKG_CAPABILITY,
         :capability,
         "requested VKG capability is outside the observe-only allowlist",
         %{capability: inspect(capability), allowed: Contract.capability_allowlist()}
       )}
    end
  end

  defp ensure_capability(contracts, capability) do
    missing =
      contracts
      |> Enum.reject(&(capability in &1.capabilities))
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
end
