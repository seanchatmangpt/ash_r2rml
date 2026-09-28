defmodule AshR2RML.VKG.Inspection do
  @moduledoc """
  Explainability projection for catalog, plan, and session state.
  """

  alias AshR2RML.VKG.{Catalog, Session}

  @spec catalog(Catalog.t()) :: map()
  def catalog(%Catalog{} = catalog) do
    %{
      catalog_sha256: catalog.sha256,
      contract_count: map_size(catalog.contracts),
      contracts:
        catalog.contracts
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {id, contract} ->
          %{
            id: id,
            source: contract.source,
            graph: contract.graph,
            source_sha256: contract.source_sha256,
            mapping_sha256: contract.mapping_sha256,
            query_sha256: contract.query_sha256,
            capabilities: contract.capabilities
          }
        end)
    }
  end

  @spec session(Session.t()) :: map()
  def session(%Session{} = session) do
    %{
      summary: Session.summary(session),
      stages:
        Enum.map(session.plan.stages, fn stage ->
          observation = Map.get(session.observations, stage.contract_id)

          %{
            contract_id: stage.contract_id,
            source: stage.source,
            graph: stage.graph,
            mapping_sha256: stage.mapping_sha256,
            query_sha256: stage.query_sha256,
            observed?: not is_nil(observation),
            observation_sha256:
              observation && Map.get(observation, :observation_sha256),
            row_count: observation && Map.get(observation, :row_count)
          }
        end),
      replay: Session.verify(session)
    }
  end
end
