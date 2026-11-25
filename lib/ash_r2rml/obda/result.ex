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
  * `quads` -- canonically sorted quad view of `triples`; see `quads/1`. Unset (`[]`) unless
    populated by the producer; `quads/1` derives it from `triples` on demand.
  * `digest` -- lowercase hex SHA-256 over the rendered R2RML Turtle, the SPARQL bytes and
    the canonical result rows; identical inputs yield an identical digest.

  ## Digest input framing (reproducible by ash_affidavit)

  The digest is SHA-256 over the concatenation of three frames, in this order:

      frame(r2rml_ttl) <> frame(sparql) <> frame(canonical_bindings)

  where `frame(bytes) = <<byte_size(bytes)::unsigned-big-64>> <> bytes`.

    1. `r2rml_ttl` -- the rendered R2RML Turtle, UTF-8 bytes, as given.
    2. `sparql` -- the SPARQL query text, UTF-8 bytes, as given (no normalization).
    3. `canonical_bindings` -- `:erlang.term_to_binary(rows, [:deterministic])` of the
       canonically sorted row list (see `canonical_sort/1`; for SELECT with `ORDER BY`
       the query order is preserved). For `:rdf` results `rows` are the statement rows.

  The output is the lowercase hex encoding of the 32-byte hash. Length prefixes make the
  framing injective: moving bytes between adjacent fields changes the digest.
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
          quads: [map()],
          kind: :bindings | :boolean | :rdf | nil,
          stats: stats(),
          digest: String.t()
        }

  @enforce_keys [:digest, :stats]
  defstruct bindings: [], triples: [], quads: [], kind: nil, stats: nil, digest: nil

  @doc """
  Canonically sorted quads for a result. Uses `quads` when populated; otherwise lifts each
  statement in `triples` into the default graph (`"graph" => nil`).

      iex> r = %AshR2RML.OBDA.Result{
      ...>   triples: [%{"s" => "b", "p" => "p", "o" => "1"}, %{"s" => "a", "p" => "p", "o" => "1"}],
      ...>   stats: %{},
      ...>   digest: ""
      ...> }
      iex> r |> AshR2RML.OBDA.Result.quads() |> Enum.map(& &1["s"])
      ["a", "b"]
  """
  @spec quads(t()) :: [map()]
  def quads(%__MODULE__{quads: [_ | _] = quads}), do: canonical_sort(quads)

  def quads(%__MODULE__{triples: triples}) do
    triples |> Enum.map(&Map.put_new(&1, "graph", nil)) |> canonical_sort()
  end

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

    :sha256
    |> :crypto.hash([frame(ttl), frame(sparql), frame(canonical)])
    |> Base.encode16(case: :lower)
  end

  defp frame(bytes), do: [<<byte_size(bytes)::unsigned-big-64>>, bytes]

  @doc "Sorts rows into a canonical, scan-order-independent order."
  @spec canonical_sort([map()]) :: [map()]
  def canonical_sort(rows), do: Enum.sort_by(rows, fn row -> row |> Enum.to_list() |> Enum.sort() end)
end
