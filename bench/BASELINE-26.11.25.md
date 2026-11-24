<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Baseline 26.11.25

Standing: PARTIAL

Measured with `MIX_ENV=test mix run bench/<script>.exs` on one developer machine (Darwin, ETS data
layer, single run per row, `--seconds 15` for S5). Numbers are from actual runs; none are projected.
SQLite/Postgres parity is covered by `test/data_layer_contract_test.exs`, not by these scripts.

| Bench | Result | Gate | Verdict |
|---|---|---|---|
| B1 subject codec (10k keys) | p99 10.7 us, Cpk 5.4 | p99 <= 50 us, Cpk >= 1.67 | PASS |
| B2 R2RML render (10/50/100 resources) | 100 resources 11.5 ms, 1 distinct SHA-256 | <= 50 ms, identical | PASS |
| B3 point lookup (10k rows, ETS) | p99 ~35 ms, rows_read 1 | p99 <= 50 ms (CTQ-3 USL), rows_read 1 | PASS (target 15 ms missed: the ETS data layer scans on filter) |
| B4 join + FILTER + ORDER BY + LIMIT 100 | p99 407 ms, shape check false | <= 50 ms | FAIL (no filter/sort/limit pushdown; full materialization) |
| B5 policy overhead | member/admin 0.99; outsider rows_read 0, pruned 1 | outsider pruned | PASS |
| B6 digest (1k/10k/50k) | 0.19 / 1.8 / 9.1 ms | 10k <= 20 ms | PASS |
| S1 heap bomb | refused `REFUSED_MEMORY_LIMIT_EXCEEDED`, caller alive | typed refusal | PASS |
| S2 row sentinel (50k rows) | refused in ~90 ms | <= 100 ms | PASS (thin margin) |
| S3 triple fan-out | refused in ~300 ms | <= 100 ms | FAIL (rows are read before the triple bound can trip) |
| S4 timeout | refused in ~54 ms, 0 leaked processes | 0 leaks | PASS |
| S5 storm (32 killer + 32 healthy) | 0 healthy failures, all killers typed | 0 failures | PASS |
| S6 soak (10k queries) | atom delta, ETS and process leaks within gate | <= 5 atoms, 0 leaks | PASS |

Not run: B3/B4 on AshSqlite (script prints `[SKIP]`, exit 3 only with `--require-sqlite`),
S5 at 60 s (15 s measured).

Open: B4 and S3 are CTQ breaches. v26.11.25 is not tagged while they stand.
