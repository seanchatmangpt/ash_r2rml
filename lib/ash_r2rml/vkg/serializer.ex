defmodule AshR2RML.VKG.Serializer do
  @moduledoc "Stable JSON projections for VKG sessions and receipts."
  alias AshR2RML.VKG.{Receipt, Result, Session}

  def receipt(%Receipt{}=r), do: %{"id"=>r.id,"plan_sha256"=>r.plan_sha256,"catalog_sha256"=>r.catalog_sha256,
    "contract_ids"=>r.contract_ids,"observation_sha256_by_contract"=>r.observation_sha256_by_contract,
    "result_sha256"=>r.result_sha256,"row_count"=>r.row_count,"previous"=>r.previous,
    "authority"=>Atom.to_string(r.authority),"standing"=>Atom.to_string(r.standing)}

  def result(%Result{}=r), do: %{"plan_sha256"=>r.plan_sha256,"rows"=>r.rows,"row_count"=>r.row_count,
    "sources"=>r.sources,"sha256"=>r.sha256,"standing"=>Atom.to_string(r.standing)}

  def session(%Session{}=s), do: %{"summary"=>stringify(Session.summary(s)),"receipt"=>receipt(s.receipt),"result"=>result(s.result)}
  def encode_receipt!(%Receipt{}=r), do: r |> receipt() |> canonical() |> Jason.encode!()
  def encode_session!(%Session{}=s), do: s |> session() |> canonical() |> Jason.encode!()

  defp canonical(map) when is_map(map), do: map |> Enum.sort_by(fn {k,_}->to_string(k) end) |> Enum.map(fn {k,v}->{to_string(k),canonical(v)} end) |> Map.new()
  defp canonical(list) when is_list(list), do: Enum.map(list,&canonical/1)
  defp canonical(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical(value), do: value
  defp stringify(map), do: Map.new(map,fn {k,v}->{to_string(k),canonical(v)} end)
end
