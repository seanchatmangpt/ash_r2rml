<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# Projection-identity benchmark receipt (v26.9.16 RFC closure)

Subject: the commit that adds this receipt, whose single parent is PR #39 head
`f1139bc4545c6b82cb7ef8c83beb2c41304b0909`. A commit cannot name its own SHA, so the subject is
bound by the SHA-256 of the measured sources instead; the receipt is valid only while these
digests match the checked-out files (`shasum -a 256 <path>`):

| Path | SHA-256 |
|---|---|
| `lib/ash_r2rml/compiler.ex` | `41787c945ec872f3affb9a91dbf42795cf8d63c202054083941761482a906cd5` |
| `lib/ash_r2rml/integrity.ex` | `d1b392837bebec7bfbec7e91c51f9ad9812048b70793f7feec7359ee6c57f5b3` |
| `bench/projection_identity.exs` | `daadc727bb41a82ba384d87debb7d36dc9a41b16a9038f0d0a1a057e806166cb` |
| `test/support/rfc_closure/connected_profile.ex` | `8ac976de4299db5307f13baf7ff317342ca8d42239aa13819e9266a8f556b373` |

Command:

```bash
BENCH_TIERS=10,100,1000 BENCH_TIME=3 MIX_ENV=test mix run bench/projection_identity.exs
```

Toolchain: Elixir 1.18.4 / OTP 27 (asdf `1.18.4-otp-27` + erlang `27.2.4`, matching
`.tool-versions`; the run printed `elixir=1.18.4 otp=27`), Benchee 1.x, macOS arm64 (Apple
M3 Max). Shared host: load average 61 (1 min) / 121 (5 min) at start, 59 / 108 at end.
Correctness verified per tier before timing: the untouched envelope is admitted, and both a
one-byte R2RML drift and an in-place IR edit are refused with `:REFUSED_PROJECTION_DRIFT`. No
external engine is exercised. Run log SHA-256:
`7c7496ba5a33f7429c849b454abdf9cb87e14f82c682eb40fb90cb4e9e44e59f`.

## Medians

| Tier | dfcm_compile | verify_projection_identity | verify / compile | manufacturing verify_staged |
|---:|---:|---:|---:|---:|
| 10 | 15.18 ms | 0.66 ms | 0.043 | 6.0 us |
| 100 | 94.62 ms | 6.77 ms | 0.072 | 6.2 us |
| 1000 | 1,083.02 ms (~3 samples in 3 s) | 127.39 ms | 0.118 | 6.1 us |

Memory per call: verify_projection_identity 0.68 MB @10, 5.57 MB @100, 54.53 MB @1000;
dfcm_compile 3.73 MB, 36.67 MB, 366.39 MB.

## What changed since the f1139bc4 receipt

The guard now also re-derives the receipted canonical digests of the SemanticIR
(`ir_sha256`) and the mapping bundle (`mapping_sha256`). A court run against f1139bc4 showed
that an in-place IR or mapping-bundle edit was admitted and could make `incremental_plan/2`
report a changed resource as reusable. Re-deriving those digests is a canonical walk plus
SHA-256 over roughly the bytes the compile sealed, so verify is no longer a small constant:
the f1139bc4 medians (51.9 us @10, 445.3 us @100) measured a guard that skipped both terms.

The compiler's canonical walk re-ran `inspect/1` on every map key. It now memoizes the sort
key per distinct key and the sorted field order per struct module, and uses the generic sort
for any struct instance whose key set differs from its module's recorded order. The canonical
term is unchanged: `test/rfc_closure_standing_wiring_test.exs` checks the digests against the
original definition. Measured at 100 resources, the IR digest fell from ~50 ms to ~4 ms.
The same walk seals the receipt, so compile got faster too: 94.6 ms here against 295.9 ms in
the f1139bc4 receipt at tier 100.

## Defect found by the first benchmark (f1139bc4)

The first implementation re-derived the session identity through
`SemanticSessionIdentity.new/1`, which re-read `AshR2RML.Compiler`'s object code from disk on
every call: 10.49 ms median @10 and 10.74 ms @100 (a ~10 ms constant, 0.7x the tier-10 compile).
The fix re-derives under the manufacturer/environment the identity recorded. A manufacturer
change stays bound into the identity digest and is refused by `admit_receipt_reuse/2`.

## Regression bound

`test/rfc_closure_projection_identity_bound_test.exs` interleaves 15 compile and 15 verify
samples per attempt and takes medians. It passes on the best of 3 attempts. It asserts
verify <= 0.2 x compile, plus absolute ceilings of 5 ms @10 and 20 ms @100. A real
regression is deterministic and fails every attempt. Both known regressions fail the bound:
the beam re-read (~10.5 ms @10, ratio ~0.7) and the unmemoized canonical walk (43 ms @100,
measured in this lane).
