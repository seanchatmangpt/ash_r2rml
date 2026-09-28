defmodule AshR2RML.VKG.Consumer.Engineering do
  @moduledoc "Engineering read model over provenance-bearing VKG results."
  alias AshR2RML.VKG.Session

  def snapshot(%Session{}=s) do
    entities=s.result.rows |> Enum.reduce(%{},fn row,acc->
      subject=get_in(row,["_vkg","subject"]) || synthetic_subject(row)
      Map.update(acc,subject,[row],&[row|&1])
    end) |> Map.new(fn {subject,rows}->{subject,Enum.reverse(rows)} end)
    %{"catalog_sha256"=>s.catalog_sha256,"plan_sha256"=>s.plan.sha256,"receipt_id"=>s.receipt.id,
      "result_sha256"=>s.result.sha256,"entity_count"=>map_size(entities),"row_count"=>s.result.row_count,
      "entities"=>entities,"sources"=>s.result.sources,"authority"=>"NONE"}
  end

  def subjects(%Session{}=s), do: s |> snapshot() |> Map.fetch!("entities") |> Map.keys() |> Enum.sort()
  def source_trace(%Session{}=s,subject), do: s.result.rows |> Enum.filter(&(get_in(&1,["_vkg","subject"])==subject)) |> Enum.map(&Map.fetch!(&1,"_vkg"))

  defp synthetic_subject(row) do
    digest=row |> Map.delete("_vkg") |> :erlang.term_to_binary([:deterministic]) |> then(&:crypto.hash(:sha256,&1)) |> Base.encode16(case: :lower)
    "urn:vkg:row:"<>binary_part(digest,0,24)
  end
end
