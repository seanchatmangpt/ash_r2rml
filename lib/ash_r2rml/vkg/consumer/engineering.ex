defmodule AshR2RML.VKG.Consumer.Engineering do
  @moduledoc """
  Engineering read model over provenance-bearing VKG results.

  Read-only and deterministic: entities are grouped by subject in sealed row
  order; rows without a subject get a stable synthetic `urn:vkg:row:` subject.
  Authority is always `"NONE"`.
  """

  alias AshR2RML.VKG.{Serializer, Session}

  @doc "Groups the session result rows into entities keyed by subject."
  @spec snapshot(Session.t()) :: map()
  def snapshot(%Session{} = session) do
    entities =
      session.result.rows
      |> Enum.reduce(%{}, fn row, acc ->
        subject = subject_of(row) || synthetic_subject(row)
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

  @doc "Sorted list of entity subjects in the session result."
  @spec subjects(Session.t()) :: [String.t()]
  def subjects(%Session{} = session) do
    session
    |> snapshot()
    |> Map.fetch!("entities")
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Provenance entries for `subject`; `[]` for an unknown or non-binary subject."
  @spec source_trace(Session.t(), String.t()) :: [map()]
  def source_trace(%Session{} = session, subject) when is_binary(subject) do
    session.result.rows
    |> Enum.filter(&(subject_of(&1) == subject))
    |> Enum.map(&Map.fetch!(&1, "_vkg"))
  end

  def source_trace(%Session{}, _subject), do: []

  # Rows are normally maps, but a snapshot must never raise on an odd row
  # (forged or hand-built sessions): non-map rows and malformed "_vkg" metadata
  # simply have no subject and get a synthetic one.
  defp subject_of(%{"_vkg" => %{"subject" => subject}}) when is_binary(subject), do: subject
  defp subject_of(_row), do: nil

  defp synthetic_subject(row) do
    payload = if is_map(row) and not is_struct(row), do: Map.delete(row, "_vkg"), else: row
    "urn:vkg:row:" <> binary_part(Serializer.digest(payload), 0, 24)
  end
end
