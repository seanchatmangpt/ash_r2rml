defmodule AshR2RML.VKG.Inspection do
  @moduledoc "Explainability projection for catalog, plan, and session state."
  alias AshR2RML.VKG.{Catalog, Session}

  def catalog(%Catalog{}=catalog) do
    %{catalog_sha256: catalog.sha256, contract_count: map_size(catalog.contracts),
      contracts: catalog.contracts |> Enum.sort_by(&elem(&1,0)) |> Enum.map(fn {id,c}->
        %{id:id,source:c.source,graph:c.graph,source_sha256:c.source_sha256,mapping_sha256:c.mapping_sha256,
          query_sha256:c.query_sha256,capabilities:c.capabilities}
      end)}
  end

  def session(%Session{}=s) do
    %{summary: Session.summary(s),
      stages: Enum.map(s.plan.stages,fn stage->
        obs=Map.get(s.observations,stage.contract_id)
        %{contract_id:stage.contract_id,source:stage.source,graph:stage.graph,mapping_sha256:stage.mapping_sha256,
          query_sha256:stage.query_sha256,observed?:not is_nil(obs),
          observation_sha256: obs && Map.get(obs,:observation_sha256),row_count: obs && Map.get(obs,:row_count)}
      end),
      replay: Session.verify(s)}
  end
end
