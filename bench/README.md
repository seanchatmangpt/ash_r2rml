<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# bench

Stress and memory benchmarks for AshR2RML. Not shipped: `bench/` is excluded from the Hex
package (`package_files/0` in `mix.exs` must not list it).

## Commands

```bash
mix run bench/stress_and_memory_bench.exs               # full suite, script defaults
mix run bench/stress_and_memory_bench.exs --seconds 10  # pass --seconds to every script
mix run bench/stress/s1_s2.exs --seconds 10             # single script
```

The umbrella runs `s1_s2`, `s3_s4`, `s5_storm`, `s6_soak` in sequence, each via its own
`mix run` process, and writes `bench/results/stress.json` and `bench/results/stress.md`.

## Layers

A layer is one real data layer behind the same Person fixture. Each lives in
`bench/stress/layers/<layer>.exs` and defines `Bench.Layer.<Camel>`:

| callback | contract |
|---|---|
| `available?/0` | `:ok` or `{:skip, reason}` |
| `setup/1` | `{:ok, ctx}` or `{:skip, reason}`; opts `rows` (default 10_000), `tenants`, `digest_rows` (default 500) |
| `scenarios/0` | `[{id, description, fun}]`; `fun.(ctx)` returns `:ok` or `{:fail, why}` |
| `canonical_digest/1` | digest of the shared healthy SPARQL result |

`ctx` is `%{specs, domain, resource, seed_rows, teardown}`. `Bench.Layer.Common.code_of/1`
normalizes `%AshR2RML.Refusal{}` and `%AshR2RML.Error{}` to a `REFUSED_*` code.

### `--layers` semantics

`--layers a,b,c` selects layers by name (the file basename under `bench/stress/layers/`).
`--layers all` runs every file found there. A layer whose `available?/0` or `setup/1` returns
`{:skip, reason}` prints `[SKIP] <layer>: <reason>` and counts as exit 3 for that layer. A
named layer with no file under `bench/stress/layers/` is also a loud skip (exit 3); only a layer
name outside the known set (`ets simple mnesia embedded sqlite csv custom postgres mysql`) exits
2 immediately. Layers run independently; one layer's skip never hides another layer's result.

### Service flags

| variable | layer | effect |
|---|---|---|
| `ASH_R2RML_POSTGRES_URL` | postgres | connection URL; unset gives `[SKIP] postgres` |
| `ASH_R2RML_MYSQL_URL` | mysql | connection URL; unset gives `[SKIP] mysql` |

In-process layers (ETS, SQLite) need no flag; a missing dependency is a loud skip.

### Scenario table

Killer scenarios pass `max_rows`, `max_triples`, `timeout_ms`, `max_heap_words` to
`AshR2RML.OBDA.query` and assert the typed refusal below. Every layer implements the same ids.

| id | scenario | expected outcome |
|---|---|---|
| S1 | heap bomb | `REFUSED_MEMORY_LIMIT_EXCEEDED`, caller alive |
| S2 | row sentinel | `REFUSED_RESULT_LIMIT_EXCEEDED` |
| S3 | triple fan-out | `REFUSED_TRIPLE_LIMIT_EXCEEDED` |
| S4 | timeout | `REFUSED_QUERY_TIMEOUT`, 0 leaked processes |
| S5 | storm (killers + healthy) | 0 healthy failures, killers typed |
| S6 | soak | no atom, ETS, or process leak |
| S7-S14 | per-layer charter scenarios | each returns `:ok` or `{:fail, why}`; ids and descriptions come from the layer's `scenarios/0` |

The per-layer cell for S1-S14 is: same expected outcome on ETS, SQLite, Postgres, MySQL, with
data-layer-specific setup only. S7-S14 definitions are UNVERIFIED here until the charter ids
are fixed in the layer files.

### Digest equivalence

Each layer seeds exactly `digest_rows` Person rows (pid `p1`..`pN`, name `Person i`, age `i`)
and runs the shared SPARQL
`SELECT ?s ?n ?a WHERE { ?s <https://schema.org/name> ?n ; <https://schema.org/age> ?a }`
through `AshR2RML.OBDA.query`. The umbrella compares every layer's `canonical_digest/1`
binary; any mismatch is FAIL (exit 1) naming the differing layers. Skipped layers are excluded
from the comparison and reported.

### Layer exit codes

Layered mode (`--layers`): 0 all scenarios pass and digests are equal; 1 any `{:fail, _}` or
digest mismatch; 3 any layer skipped (unavailable service, crashed setup, or missing layer file),
never a silent pass; 2 only for an unknown layer name. Failure outranks skip: 1 > 3 > 0.
Legacy script mode keeps 1 > 2 > 3 > 0 (2 = script file missing).

## CTQ / USL

| script | scenario | CTQ (critical to quality) | USL (upper spec limit) |
|---|---|---|---|
| s1_s2 | S1/S2 | defined in the script header | defined in the script header |
| s3_s4 | S3/S4 | defined in the script header | defined in the script header |
| s5_storm | S5 | defined in the script header | defined in the script header |
| s6_soak | S6 | defined in the script header | defined in the script header |

Each script owns its CTQ and USL values and fails (exit 1) when a measured value exceeds its
USL; the umbrella only aggregates exit codes.

## Exit-code discipline

| code | meaning |
|---|---|
| 0 | PASS |
| 1 | FAIL (any USL breach or crash; any other nonzero code is treated as FAIL) |
| 2 | SUBJECT MISSING (legacy: script file absent; layered: unknown layer name) |
| 3 | LOUD SKIP (reason printed; never a silent pass) |

Aggregate precedence: 1 > 2 > 3 > 0.
