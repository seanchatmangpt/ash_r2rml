# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Result do
  @moduledoc """
  Envelope returned by `AshR2RML.OBDA.query/3`.

  * `bindings` -- canonically sorted SELECT rows (or the single ASK row).
  * `triples` -- canonically sorted CONSTRUCT/DESCRIBE statements.
  * `kind` -- `:bindings | :boolean | :rdf`, the underlying observation kind.
  * `stats` -- `%{rows_read, triples_emitted, duration_us, resources_pruned_by_policy}`.
  * `digest` -- lowercase hex SHA-256 over the rendered R2RML Turtle, the SPARQL bytes and
    the canonical result rows; identical inputs yield an identical digest.
  """

  @type stats :: %{
          rows_read: non_neg_integer(),
          triples_emitted: non_neg_integer(),
          duration_us: non_neg_integer(),
          resources_pruned_by_policy: non_neg_integer()
        }

  @type t :: %__MODULE__{
          bindings: [map()],
          triples: [map()],
          kind: :bindings | :boolean | :rdf | nil,
          stats: stats(),
          digest: String.t()
        }

  @enforce_keys [:digest, :stats]
  defstruct bindings: [], triples: [], kind: nil, stats: nil, digest: nil

  @doc """
  Computes the envelope digest from the rendered R2RML Turtle, the SPARQL text and the
  canonical rows.

      iex> a = AshR2RML.OBDA.Result.digest("ttl", "ASK {}", [%{"x" => 1}])
      iex> a == AshR2RML.OBDA.Result.digest("ttl", "ASK {}", [%{"x" => 1}])
      true
      iex> a == AshR2RML.OBDA.Result.digest("ttl", "ASK {}", [%{"x" => 2}])
      false
  """
  @spec digest(binary(), binary(), [map()]) :: String.t()
  def digest(ttl, sparql, rows) when is_binary(ttl) and is_binary(sparql) and is_list(rows) do
    canonical = :erlang.term_to_binary(rows, [:deterministic])

    [ttl, sparql, canonical]
    |> Enum.reduce(:crypto.hash_init(:sha256), fn part, acc ->
      acc
      |> then(&:crypto.hash_update(&1, <<byte_size(part)::64>>))
      |> then(&:crypto.hash_update(&1, part))
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc "Sorts rows into a canonical, scan-order-independent order."
  @spec canonical_sort([map()]) :: [map()]
  def canonical_sort(rows), do: Enum.sort_by(rows, fn row -> row |> Enum.to_list() |> Enum.sort() end)
end
