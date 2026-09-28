defmodule AshR2RML.VKG.Consumer.Engineering do
  @moduledoc """
  Engineering read model over provenance-bearing VKG results.
  """

  alias AshR2RML.VKG.Session

  @spec snapshot(Session.t()) :: map()
  def snapshot(%Session{} = session) do
    entities =
      session.result.rows
      |> Enum.reduce(%{}, fn row, acc ->
        subject = get_in(row, ["_vkg", "subject"]) || synthetic_subject(row)
        Map.update(acc, subject, [row], &[row | &1])
      end)
      |> Map.new(fn {subject, rows} ->
        {subject, Enum.reverse(rows)}
      end)

    %{
      "catalog_sha256" => session.catalog_sha256,
      "plan_sha256" => session.plan.sha256,
      "receipt_id" => session.receipt.id,
      "result_sha256" => session.result.sha256,
      "entity_count" => map_size(entities),
      "row_count" => session.result.row_count,
      "entities" => entities,
      "sources" => session.result.sources,
      "authority" => "NONE"
    }
  end

  @spec subjects(Session.t()) :: [String.t()]
  def subjects(%Session{} = session) do
    session
    |> snapshot()
    |> Map.fetch!("entities")
    |> Map.keys()
    |> Enum.sort()
  end

  @spec source_trace(Session.t(), String.t()) :: [map()]
  def source_trace(%Session{} = session, subject) do
    session.result.rows
    |> Enum.filter(&(get_in(&1, ["_vkg", "subject"]) == subject))
    |> Enum.map(&Map.fetch!(&1, "_vkg"))
  end

  defp synthetic_subject(row) do
    digest =
      row
      |> Map.delete("_vkg")
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "urn:vkg:row:" <> binary_part(digest, 0, 24)
  end
end
