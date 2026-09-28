defmodule AshR2RML.VKG.Consumer.GraphQL do
  @moduledoc """
  Deterministic read-only GraphQL connection projection over a VKG session.
  """

  alias AshR2RML.VKG.Session

  @spec connection(Session.t(), keyword()) :: map()
  def connection(%Session{} = session, opts \\ []) do
    first = Keyword.get(opts, :first, session.result.row_count)
    after_cursor = Keyword.get(opts, :after)

    rows =
      session.result.rows
      |> drop_after(after_cursor)
      |> Enum.take(max(first, 0))

    edges =
      Enum.map(rows, fn row ->
        %{
          "cursor" => cursor(row),
          "node" => Map.delete(row, "_vkg"),
          "provenance" => Map.fetch!(row, "_vkg")
        }
      end)

    %{
      "edges" => edges,
      "pageInfo" => %{
        "hasNextPage" => length(rows) < session.result.row_count,
        "endCursor" =>
          edges
          |> List.last()
          |> then(fn
            nil -> nil
            edge -> edge["cursor"]
          end)
      },
      "receiptId" => session.receipt.id,
      "resultSha256" => session.result.sha256,
      "authority" => "NONE"
    }
  end

  defp drop_after(rows, nil), do: rows

  defp drop_after(rows, after_cursor) do
    case Enum.find_index(rows, &(cursor(&1) == after_cursor)) do
      nil -> rows
      index -> Enum.drop(rows, index + 1)
    end
  end

  defp cursor(row) do
    digest =
      get_in(row, ["_vkg", "row_sha256"]) ||
        row
        |> :erlang.term_to_binary([:deterministic])
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

    Base.url_encode64(digest, padding: false)
  end
end
