# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ParityReceipt do
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
    :session_sha256,
    :left_observation_sha256,
    :right_observation_sha256,
    :observed?,
    :verified?,
    :receipt_sha256,
    left_count: 0,
    right_count: 0,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          kind: :sparql_sql,
          subject: term(),
          left_system: atom() | String.t(),
          right_system: atom() | String.t(),
          left_query_sha256: String.t() | nil,
          right_query_sha256: String.t() | nil,
          left_result_sha256: String.t(),
          right_result_sha256: String.t(),
          fixture_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          session_sha256: String.t() | nil,
          left_observation_sha256: String.t() | nil,
          right_observation_sha256: String.t() | nil,
          observed?: boolean(),
          verified?: boolean(),
          receipt_sha256: String.t(),
          left_count: non_neg_integer(),
          right_count: non_neg_integer(),
          metadata: map()
        }
end

defmodule AshR2RML.Parity do
  @moduledoc """
  Deterministic semantic-result comparator for side-by-side cutover evidence.

  Query execution is intentionally outside this module. Callers execute the
  admitted SQL/SPARQL queries, then pass their observed rows here. The
  comparator normalizes result multisets and emits a stable receipt that can be
  attached to `AshR2RML.CompilationReceipt`.

  `:session_sha256` binds the result comparison to the exact DfCM semantic
  session. Callers may omit it, but strict DfCM witness admission will
  refuse an unbound receipt for crown/cutover standing.

  Empty-string cells are collapsed to "unbound" only for rows declared as CSV via the
  `:left_csv_rows` / `:right_csv_rows` metadata flags. All other rows keep `""` as a bound value.
  A receipt is `observed?: true` only when `metadata.observed?` is `true` and both observation
  hashes are present.
  """

  alias AshR2RML.ParityReceipt

  @doc """
  Compares two observed row lists as multisets and returns a `ParityReceipt`.

  `metadata` keys may be atoms or strings. `verified?` is true when the normalized
  multisets are equal; `observed?` follows the rule in the moduledoc.
  """
  @spec compare(:sparql_sql, term(), list(), list(), map()) :: ParityReceipt.t()
  def compare(kind, subject, left_rows, right_rows, metadata \\ %{})
      when kind == :sparql_sql and is_list(left_rows) and is_list(right_rows) do
    left = normalize_multiset(left_rows, csv?: get(metadata, :left_csv_rows) == true)
    right = normalize_multiset(right_rows, csv?: get(metadata, :right_csv_rows) == true)
    left_hash = sha256(left)
    right_hash = sha256(right)
    left_observation_sha256 = get(metadata, :left_observation_sha256)
    right_observation_sha256 = get(metadata, :right_observation_sha256)

    observed? =
      get(metadata, :observed?) == true and
        present_hash?(left_observation_sha256) and
        present_hash?(right_observation_sha256)

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
      session_sha256: get(metadata, :session_sha256),
      left_observation_sha256: left_observation_sha256,
      right_observation_sha256: right_observation_sha256,
      observed?: observed?,
      verified?: left == right,
      left_count: length(left_rows),
      right_count: length(right_rows),
      metadata:
        Map.drop(metadata, [
          :left_query,
          :right_query,
          :session_sha256,
          :left_observation_sha256,
          :right_observation_sha256,
          :observed?,
          "left_query",
          "right_query",
          "session_sha256",
          "left_observation_sha256",
          "right_observation_sha256",
          "observed?"
        ])
    }

    %{receipt | receipt_sha256: sha256(canonical(Map.from_struct(receipt)))}
  end

  @doc "Normalize an unordered result multiset while preserving duplicate cardinality."
  @spec normalize_multiset(list(), keyword()) :: list()
  def normalize_multiset(rows, opts \\ []) do
    csv? = Keyword.get(opts, :csv?, false) == true

    rows
    |> Enum.map(&canonical(&1, csv?))
    |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))
  end

  # One-arity form is used for the receipt body, where CSV collapsing never applies.
  defp canonical(value), do: canonical(value, false)

  defp canonical(%Decimal{} = decimal, _csv?), do: Decimal.to_string(decimal, :normal)
  defp canonical(%DateTime{} = datetime, _csv?), do: DateTime.to_iso8601(datetime)
  defp canonical(%NaiveDateTime{} = datetime, _csv?), do: NaiveDateTime.to_iso8601(datetime)
  defp canonical(%Date{} = date, _csv?), do: Date.to_iso8601(date)
  defp canonical(%_{} = struct, csv?), do: struct |> Map.from_struct() |> canonical(csv?)

  # A SPARQL binding row can express "this variable has no value here" two
  # observably different ways depending on the execution surface: the local
  # in-process engine (`AshR2RML.SPARQL.Local`) simply omits the key from the
  # solution map, while a CSV-emitting result surface must
  # still print every header column and renders an unbound variable as an
  # empty cell (`""`) — the SPARQL 1.1 CSV results format itself cannot
  # distinguish "unbound" from "bound to the empty string". For rows declared
  # CSV (`csv?`), drop empty-string-valued keys so both representations
  # collapse to the same canonical shape. Non-CSV rows keep `""` as a value.
  defp canonical(map, csv?) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> csv? and value == "" end)
    |> Enum.map(fn {key, value} -> {to_string(key), canonical(value, csv?)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp canonical(list, csv?) when is_list(list), do: Enum.map(list, &canonical(&1, csv?))

  defp canonical(tuple, csv?) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canonical(&1, csv?))

  defp canonical(value, _csv?) when is_atom(value) and value not in [true, false, nil],
    do: Atom.to_string(value)

  defp canonical(value, _csv?), do: value

  defp present_hash?(value), do: is_binary(value) and value != ""

  defp query_hash(nil), do: nil
  defp query_hash(query), do: sha256(to_string(query))

  defp default_left(:sparql_sql), do: :sparql
  defp default_right(:sparql_sql), do: :sql

  defp get(map, key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end
