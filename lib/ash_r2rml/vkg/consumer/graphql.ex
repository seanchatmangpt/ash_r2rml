defmodule AshR2RML.VKG.Consumer.GraphQL do
  @moduledoc """
  Deterministic read-only GraphQL connection projection over a VKG session.

  Rows are paged in the sealed result order. Cursors are opaque, unique per
  edge and bound to the result digest: `base64url("<result-sha16>:<index>:<row-sha>")`.
  A cursor from a different result, a tampered cursor, or a malformed one is
  refused with `REFUSED_VKG_QUERY_PLAN` (subject `:cursor`); it never restarts
  pagination silently. `:first` must be a non-negative integer.

  `page/2` is the canonical `{:ok, connection} | {:error, Refusal.t()}` API;
  `connection/2` is the backward compatible form that returns the bare map on
  success and `{:error, Refusal.t()}` on refusal.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.VKG.Session

  @spec page(Session.t(), keyword()) :: {:ok, map()} | {:error, Refusal.t()}
  def page(session, opts \\ [])

  def page(%Session{} = session, opts) when is_list(opts) do
    rows = session.result.rows
    first = Keyword.get(opts, :first, length(rows))
    after_cursor = Keyword.get(opts, :after)

    with :ok <- validate_first(first),
         {:ok, start} <- start_index(session, rows, after_cursor) do
      remaining = rows |> Enum.with_index() |> Enum.drop(start)
      page_rows = Enum.take(remaining, first)
      edges = Enum.map(page_rows, fn {row, index} -> edge(session, row, index) end)

      {:ok,
       %{
         "edges" => edges,
         "pageInfo" => %{
           "hasNextPage" => length(remaining) > first,
           "hasPreviousPage" => start > 0,
           "endCursor" => edges |> List.last() |> end_cursor()
         },
         "receiptId" => session.receipt.id,
         "resultSha256" => session.result.sha256,
         "authority" => "NONE"
       }}
    end
  end

  def page(%Session{}, opts), do: refuse(:options, "GraphQL options must be a keyword list", %{got: inspect(opts)})
  def page(other, _opts), do: refuse(:session, "GraphQL connection requires a VKG session", %{got: inspect(other)})

  @spec connection(Session.t(), keyword()) :: map() | {:error, Refusal.t()}
  def connection(session, opts \\ []) do
    case page(session, opts) do
      {:ok, connection} -> connection
      {:error, _} = error -> error
    end
  end

  defp end_cursor(nil), do: nil
  defp end_cursor(edge), do: edge["cursor"]

  defp edge(session, row, index) do
    %{
      "cursor" => cursor(session, row, index),
      "node" => Map.delete(row, "_vkg"),
      "provenance" => Map.get(row, "_vkg")
    }
  end

  defp validate_first(first) when is_integer(first) and first >= 0, do: :ok

  defp validate_first(first),
    do: refuse(:first, "GraphQL first must be a non-negative integer", %{got: inspect(first)})

  defp start_index(_session, _rows, nil), do: {:ok, 0}

  defp start_index(session, rows, cursor) when is_binary(cursor) do
    with {:ok, index, row_sha} <- decode(session, cursor),
         %{} = row <- Enum.at(rows, index),
         true <- row_digest(row) == row_sha do
      {:ok, index + 1}
    else
      _ -> invalid_cursor(cursor)
    end
  end

  defp start_index(_session, _rows, cursor), do: invalid_cursor(cursor)

  defp decode(session, cursor) do
    with {:ok, raw} <- Base.url_decode64(cursor, padding: false),
         [prefix, index, row_sha] <- String.split(raw, ":", parts: 3),
         true <- prefix == result_prefix(session),
         {index, ""} when index >= 0 <- Integer.parse(index) do
      {:ok, index, row_sha}
    else
      _ -> :error
    end
  end

  defp invalid_cursor(cursor),
    do:
      refuse(:cursor, "GraphQL cursor is malformed or does not belong to this result", %{
        cursor: inspect(cursor)
      })

  defp cursor(session, row, index) do
    Base.url_encode64("#{result_prefix(session)}:#{index}:#{row_digest(row)}", padding: false)
  end

  defp result_prefix(session), do: binary_part(session.result.sha256, 0, 16)

  defp row_digest(row) do
    get_in(row, ["_vkg", "row_sha256"]) ||
      row
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
  end

  defp refuse(subject, detail, evidence),
    do: {:error, Refusal.new(:REFUSED_VKG_QUERY_PLAN, subject, detail, evidence)}
end
