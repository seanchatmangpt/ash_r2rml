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
| 2 | SUBJECT MISSING (script or subject under test absent) |
| 3 | LOUD SKIP (reason printed; never a silent pass) |

Aggregate precedence: 1 > 2 > 3 > 0.
