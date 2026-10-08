# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Delta do
  @spec_budget_ms 20
  @default_iterations 7

  @moduledoc """
  Differential ΔG projection over materialized `RDF.Graph`s: what changed between a
  previous materialization and the current one, plus a deterministic root digest of
  the current graph.

  ## Diff semantics

  `diff/2` is plain triple-set algebra over `{s, p, o}` tuples (`RDF.Triple.t()`),
  with `RDF.Graph`'s own deduplication providing the set semantics (a `RDF.Graph`
  cannot hold the same {s,p,o} twice, so both inputs are already sets):

      added   = new − old
      removed = old − new
      unchanged_count = |old ∩ new|

  `added`/`removed` are returned as lists sorted by term order for a deterministic
  result (diff(old, new) twice yields byte-identical maps). The digest is the only
  content-derived field; the sets are materialized so callers can apply them without
  re-diffing.

  ## Root digest (Blake3/SHA-256 hedge, resolved)

  The spec's "Blake3/SHA-256" hedge is resolved here to **SHA-256**: no Blake3
  implementation exists anywhere in the fleet's Elixir/Rust dependency surface
  (verified against `mix.lock` and the graphlaw crates), so the root digest is

      "sha256:" <> hex(:crypto.hash(:sha256, sorted_canonical_ntriples(new_graph)))

  where the serialization is `RDF.NTriples.Encoder.encode/2` with `sort: true` --
  the encoder's own code-point sort of the canonical N-Triples lines. Hex is
  lowercase. Blake3 adoption, if it ever happens, is a separate spec decision; the
  `:"sha256:"` prefix makes a future algorithm change self-describing.

  Determinism scope (honest boundary): sorted N-Triples is deterministic for graphs
  whose terms are fully determined -- which is exactly what `AshR2RML.OBDA.InMemory`
  materializes (IRIs and typed/string literals, no blank nodes -- every triple is
  built from `RDF.iri/1`/`RDF.literal/1` over real row values). For graphs *with*
  blank nodes, sorted N-Triples is label-dependent and NOT isomorphism-stable. When a
  consumer needs a blank-node-stable, RDFC-1.0 root -- e.g. to match graphlaw's
  `LawState` ids -- compute it with the wasm `canonical` op instead, exposed as
  `AshGraphLaw.Calculation.CanonicalId` (which returns the same `"sha256:..."` shape
  over the RDFC-1.0 canonical form; see
  `ash_graphlaw/lib/ash_graphlaw/calculation/canonical_id.ex`). This is a
  cross-reference, not a dependency: `AshR2RML.Delta` deliberately depends on
  nothing outside `:crypto` and `:rdf`, and rdf-ex 3.0.1's own bundled
  `RDF.Canonicalization` is *not* used here because the deterministic base for
  bnode-free graphs needs no canonicalization algorithm at all.

  ## Wasmex memory surface (zero-copy disclosure)

  The spec's zero-copy goal for a future wasm-based digest path is **infeasible on
  wasmex 0.15.1** and is not shipped. wasmex 0.15.1's entire host memory surface is
  `Wasmex.Memory.read_binary/4` and `Wasmex.Memory.write_binary/4` (see ash_graphlaw
  `lib/ash_graphlaw/host.ex:531` and `:579`) -- both byte-copy across the NIF
  boundary in both directions (host→wasm on write, wasm→host on read); there is no
  memory-view/zero-copy API. So the honest v1 contract is:

  1. **Pinned-sha slice contract**: the digest is computed over a pinned
     serialization (sorted canonical N-Triples, above) whose encoder version is
     pinned by this repo's `mix.lock` (`rdf 3.0.1`), and the `"sha256:"` prefix pins
     the algorithm. A consumer can reproduce the digest byte-identically from any
     serialization of the same graph.
  2. **Measured copy cost, disclosed** (see `test/delta_budget_test.exs`, whose
     measured medians are recorded in the budget table below): the digest path costs
     one serialization + one hash over the whole graph -- the same asymptotics the
     wasm byte-copy path would pay, without the two extra wasm-boundary copies.

  The named upgrade path if true zero-copy is ever required: a dedicated NIF that
  holds the wasmtime `Store`/`Memory` directly and exposes an owned binary sub-view,
  or replacing wasmex with a direct `wasmtime` host. Neither is built in this lane;
  both are new-NIF-scale decisions, not options on the existing 0.15.1 surface.

  ## Measured budgets (this machine, macOS/Darwin 25.2.0, Elixir #{System.version()})

  From `test/delta_budget_test.exs` (real `Ash.DataLayer.Ets` rows, real
  `materialize_many/2`, median of #{@default_iterations} iterations; the test asserts
  the spec budget of ≤ #{@spec_budget_ms} ms at the 100-row tier directly and a ≤
  5×-median outlier guard per tier):

  | tier (rows) | diff+digest (ms, median) | materialize+diff combined (ms, median) |
  |-------------|--------------------------|----------------------------------------|
  | 10          | 0.138                    | 0.505                                  |
  | 100         | 1.501                    | 4.540                                  |
  | 1000        | 17.087                   | 45.925                                 |

  CI multiplier: the test's per-tier regression guard is 5× the measured median of
  the same run (documented here per the spec's "generous CI multiplier"), which
  absorbs scheduler noise without weakening the absolute 20 ms spec budget at the
  100-row tier.
  """

  @typedoc "The Δ between two materialized graphs plus the current graph's root digest."
  @type t :: %{
          required(:added) => [RDF.Triple.t()],
          required(:removed) => [RDF.Triple.t()],
          required(:unchanged_count) => non_neg_integer(),
          required(:root_digest) => String.t()
        }

  @doc """
  Diffs `old_graph` against `new_graph` (triple-set algebra; see moduledoc) and
  returns the delta map with `root_digest` over `new_graph`.
  """
  @spec diff(RDF.Graph.t(), RDF.Graph.t()) :: t()
  def diff(%RDF.Graph{} = old_graph, %RDF.Graph{} = new_graph) do
    old_set = triple_set(old_graph)
    new_set = triple_set(new_graph)

    %{
      added: new_set |> MapSet.difference(old_set) |> Enum.sort(),
      removed: old_set |> MapSet.difference(new_set) |> Enum.sort(),
      unchanged_count: old_set |> MapSet.intersection(new_set) |> MapSet.size(),
      root_digest: root_digest(new_graph)
    }
  end

  @doc """
  The deterministic root digest of `graph`: `"sha256:" <> lowercase-hex` over the
  sorted canonical N-Triples serialization (see moduledoc for the determinism scope
  and the RDFC-1.0 cross-reference).
  """
  @spec root_digest(RDF.Graph.t()) :: String.t()
  def root_digest(%RDF.Graph{} = graph) do
    {:ok, ntriples} = RDF.NTriples.Encoder.encode(graph, sort: true)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, ntriples), case: :lower)
  end

  # An RDF.Graph is already a triple set (no duplicate {s,p,o}); RDF.Graph.triples/1
  # yields the {s,p,o} tuples directly, so this is the whole normalization.
  defp triple_set(%RDF.Graph{} = graph), do: MapSet.new(RDF.Graph.triples(graph))

  @doc false
  def spec_budget_ms, do: @spec_budget_ms

  @doc false
  def default_iterations, do: @default_iterations
end
