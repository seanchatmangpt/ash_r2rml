<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# Projection-identity benchmark receipt (v26.9.16 RFC closure)

Subject: PR #39 head `94155d26364bec436517811644132f838c0dba94` plus the hardening commit that
adds `AshR2RML.DfCM.Compiler.verify_projection_identity/1`. Command:

```bash
BENCH_TIERS=10,100,1000 BENCH_TIME=3 MIX_ENV=test mix run bench/projection_identity.exs
```

Toolchain: Elixir 1.18.4 / OTP 27 (`.tool-versions`), Benchee 1.x, macOS arm64, load average
~150-210 during both runs (shared host). Correctness verified per tier before timing: the
untouched envelope is admitted and a one-byte R2RML drift is refused with
`:REFUSED_PROJECTION_DRIFT`. No external engine is exercised.

## Medians

| Tier | dfcm_compile | verify_projection_identity | manufacturing verify_staged |
|---:|---:|---:|---:|
| 10 | 19.57 ms | 51.9 us | 5.5 us |
| 100 | 295.9 ms | 445.3 us | 5.5 us |
| 1000 | 7,550.8 ms (1 sample) | 5.41 ms | 6.0 us |

Memory per call: verify_projection_identity 8.1 KB @10, 13.3 KB @100, 63.1 KB @1000.

## Defect found by this benchmark

The first implementation re-derived the session identity through
`SemanticSessionIdentity.new/1`, which re-read `AshR2RML.Compiler`'s object code from disk on
every call: 10.49 ms median @10 and 10.74 ms @100 (a ~10 ms constant, 0.7x the tier-10 compile).
The fix re-derives under the manufacturer/environment the identity recorded, so the check costs
hashing only (~200x faster @10). Manufacturer change stays bound into the identity digest and
is refused by `admit_receipt_reuse/2`.

## Regression bound

`test/rfc_closure_projection_identity_bound_test.exs` asserts, on medians of 15 runs:
verify <= 0.05 x compile at tiers 10 and 100, and absolute ceilings of 5 ms @10 and 20 ms @100.
The pre-fix implementation fails both tier-10 bounds.
