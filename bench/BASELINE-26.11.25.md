<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Baseline 26.11.25

Standing: PARTIAL

Measured with `MIX_ENV=test mix run bench/<script>.exs` on one developer machine (Darwin, single run per
row; S5 at the full 60 s). Numbers are from actual runs on the working tree that became v26.11.25; none are
projected. Gates marked "relaxed" differ from the charter USL and the charter value is stated.

| Bench | Result | Gate | Verdict |
|---|---|---|---|
| B1 subject codec (10k keys) | p99 5-11 us, Cpk 4.5-5.4 | p99 <= 50 us, Cpk >= 1.67 | PASS |
| B2 R2RML render (10/50/100 resources) | 100 resources 11.5 ms, 1 distinct SHA-256 | <= 50 ms, identical | PASS |
| B3 point lookup, ETS (10k rows) | p99 ~35 ms, rows_read 1 | <= 50 ms (CTQ-3 USL) | PASS (15 ms target missed: Ash ETS scans on filter) |
| B3 point lookup, AshSqlite (10k rows) | p99 0.5 ms, rows_read 1 | <= 150 ms | PASS |
| B4 join+FILTER+ORDER BY+LIMIT 100, ETS | p99 ~110 ms, rows_read 601, shape ok | relaxed 150 ms (charter 50 ms) | PASS relaxed / charter MISS (Ash ETS filters and sorts 10k records in Elixir) |
| B4 join+FILTER+ORDER BY+LIMIT 100, AshSqlite | p99 ~16 ms, rows_read 601, shape ok | <= 150 ms | PASS |
| B5 policy overhead | member/admin 0.99; outsider rows_read 0, pruned 1 | outsider pruned | PASS |
| B6 digest (1k/10k/50k) | 0.19 / 1.8 / 9.1 ms | 10k <= 20 ms | PASS |
| S1 heap bomb | `REFUSED_MEMORY_LIMIT_EXCEEDED`, caller alive | typed refusal | PASS |
| S2 row sentinel (50k rows) | refused in ~88 ms | <= 100 ms | PASS (thin margin) |
| S3 triple fan-out (5000 x 31) | refused in ~148 ms | relaxed 200 ms (charter 100 ms) | PASS relaxed / charter MISS (Ash ETS casts the whole table before the clamped limit) |
| S4 timeout | refused in ~54 ms, 0 leaked processes | 0 leaks | PASS |
| S5 storm 60 s (32 killer + 32 healthy) | 0 healthy failures, all killers typed | 0 failures | PASS |
| S6 soak (10k queries) | atom, ETS and process deltas within gate | <= 5 atoms, 0 leaks | PASS |

Behavior fixes the benches exposed: typed literals are now emitted from declared datatypes (numeric FILTER
returned zero rows before); `max_rows`/`max_triples` are forwarded from `OBDA.query`; IRI object templates over
non-attributes are refused; SQLite string ORDER BY pushdown allowed (BINARY collation).

Not measured: Mnesia, embedded, CSV, custom and MySQL stress (`bench/stress/layers/*` are written but were
not executed), Postgres stress (S8), SQLite WAL contention (S7). ETS/Simple/CSV/SQLite/Postgres result
equivalence is asserted by `test/cross_layer_equivalence_all_test.exs` over bindings; the digest itself seals
the rendered R2RML, whose TriplesMap names carry the module name, so digests differ across layers by design.

## Per-layer matrix

Standing: UNVERIFIED. Every cell awaits a coordinator run; no number below is measured.

| Scenario | ETS | SQLite | Postgres | MySQL |
|---|---|---|---|---|
| S1 heap bomb | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| S2 row sentinel | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| S3 triple fan-out | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| S4 timeout | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| S5 storm | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| S6 soak | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| S7-S14 | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |
| canonical digest (500 rows) | UNVERIFIED | UNVERIFIED | UNVERIFIED | UNVERIFIED |

Open: two relaxed gates (B4 ETS, S3 ETS) and the unexecuted per-layer matrix above.
