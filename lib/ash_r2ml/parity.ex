# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.ParityReceipt do
  @moduledoc "Receipt for an observed result-equivalence comparison."

  defstruct [
    :kind,
    :subject,
    :left_system,
    :right_system,
    :left_query_sha256,
    :right_query_sha256,
    :left_result_sha256,
    :right_result_sha256,
    :fixture_sha256,
    :mapping_sha256,
    :verified?,
    :receipt_sha256,
    left_count: 0,
    right_count: 0,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          kind: :sparql_sql | :neo4j_postgres,
          subject: term(),
          left_system: atom() | String.t(),
          right_system: atom() | String.t(),
          left_query_sha256: String.t() | nil,
          right_query_sha256: String.t() | nil,
          left_result_sha256: String.t(),
          right_result_sha256: String.t(),
          fixture_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          verified?: boolean(),
          receipt_sha256: String.t(),
          left_count: non_neg_integer(),
          right_count: non_neg_integer(),
          metadata: map()
        }
end

defmodule AshR2ml.Parity do
  @moduledoc """
  Deterministic semantic-result comparator for side-by-side cutover evidence.

  Query execution is intentionally outside this module. Callers execute the
  admitted SQL/SPARQL/Cypher queries, then pass their observed rows here. The
  comparator normalizes result multisets and emits a stable receipt that can be
  attached to `AshR2ml.CompilationReceipt`.
  """

  alias AshR2ml.ParityReceipt

  @spec compare(:sparql_sql | :neo4j_postgres, term(), list(), list(), map()) :: ParityReceipt.t()
  def compare(kind, subject, left_rows, right_rows, metadata \\ %{})
      when kind in [:sparql_sql, :neo4j_postgres] and is_list(left_rows) and is_list(right_rows) do
    left = normalize_multiset(left_rows)
    right = normalize_multiset(right_rows)
    left_hash = sha256(left)
    right_hash = sha256(right)

    receipt = %ParityReceipt{
      kind: kind,
      subject: subject,
      left_system: get(metadata, :left_system) || default_left(kind),
      right_system: get(metadata, :right_system) || default_right(kind),
      left_query_sha256: query_hash(get(metadata, :left_query)),
      right_query_sha256: query_hash(get(metadata, :right_query)),
      left_result_sha256: left_hash,
      right_result_sha256: right_hash,
      fixture_sha256: get(metadata, :fixture_sha256),
      mapping_sha256: get(metadata, :mapping_sha256),
      verified?: left == right,
      left_count: length(left_rows),
      right_count: length(right_rows),
      metadata: Map.drop(metadata, [:left_query, :right_query, "left_query", "right_query"])
    }

    %{receipt | receipt_sha256: sha256(canonical(Map.from_struct(receipt)))}
  end

  @doc "Normalize an unordered result multiset while preserving duplicate cardinality."
  def normalize_multiset(rows) do
    rows
    |> Enum.map(&canonical/1)
    |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))
  end

  defp canonical(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp canonical(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp canonical(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp canonical(%Date{} = date), do: Date.to_iso8601(date)
  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(value) when is_atom(value) and value not in [true, false, nil], do: Atom.to_string(value)
  defp canonical(value), do: value

  defp query_hash(nil), do: nil
  defp query_hash(query), do: sha256(to_string(query))

  defp default_left(:sparql_sql), do: :sparql
  defp default_left(:neo4j_postgres), do: :neo4j
  defp default_right(:sparql_sql), do: :sql
  defp default_right(:neo4j_postgres), do: :postgres

  defp get(map, key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end
