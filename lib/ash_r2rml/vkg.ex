defmodule AshR2RML.VKG do
  @moduledoc """
  Public observe-only Virtual Knowledge Graph facade.

  Preserves source manifest -> admitted catalog -> deterministic plan -> bounded
  execution -> provenance-bearing result -> receipt -> replay verification.
  """

  alias AshR2RML.VKG.{Catalog, Executor, Planner, Receipt, Session}

  @spec query([String.t()], keyword()) :: {:ok, Session.t()} | {:error, term()}
  def query(contract_ids, opts \\ []) when is_list(contract_ids) do
    root = Keyword.get(opts, :root, AshR2RML.VKG.Manifest.default_root())
    query_opts = Keyword.drop(opts, [:root, :previous_receipt])

    with {:ok, catalog} <- Catalog.load(root),
         {:ok, plan} <- Planner.plan(catalog, contract_ids, query_opts),
         {:ok, result, observations} <- Executor.execute(plan, query_opts) do
      receipt = Receipt.build(plan, result, observations, Keyword.get(opts, :previous_receipt))
      {:ok, Session.new(catalog, plan, result, observations, receipt)}
    end
  end

  @spec query_all(keyword()) :: {:ok, Session.t()} | {:error, term()}
  def query_all(opts \\ []) do
    root = Keyword.get(opts, :root, AshR2RML.VKG.Manifest.default_root())

    with {:ok, catalog} <- Catalog.load(root) do
      query(Catalog.ids(catalog), Keyword.put(opts, :root, root))
    end
  end

  @spec catalog(keyword()) :: {:ok, Catalog.t()} | {:error, term()}
  def catalog(opts \\ []) do
    Catalog.load(Keyword.get(opts, :root, AshR2RML.VKG.Manifest.default_root()))
  end
end
