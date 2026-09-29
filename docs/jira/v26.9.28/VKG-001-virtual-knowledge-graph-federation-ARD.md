# ARD v26.9.28 — VKG-001: Observe-only Virtual Knowledge Graph Federation

**Status:** IMPLEMENTED with named residual risks
**Release:** v26.9.28 (workflow subject frozen at `40d181f`; later changes need re-pin)
**Authority ceiling:** observe-only, `:NONE`; no DO

## Architecture objective

Normalize sources to a contract/plan IR first, verify identity and digests second, execute third.

## Components

| Component | Module |
|---|---|
| Manifest loader | `AshR2RML.VKG.Manifest`, `SourceIdentity` |
| Contracts and admission | `Contract`, `Catalog`, `Compatibility`, `Registry` |
| Planning | `Planner`, `QueryPlan` |
| Execution | `Executor`, `Engine.Ontop`, `Batch` |
| Evidence | `Result`, `Provenance`, `Receipt`, `Session`, `Serializer`, `Metrics` |
| Verification | `Replay`, `Inspection` |
| Consumers | `Consumer.Graphql`, `Consumer.Engineering` |
| Data | `priv/vkg/{sources,mappings,contracts,queries,shapes,ontology}` |

## Control/data flow

manifest -> catalog -> plan -> executor (per-stage engine call) -> result -> receipt -> replay verify.

## Invariants

1. Digests are computed from exact bytes at load, never hand-copied.
2. Plan digest excludes filesystem paths and the catalog binding; it is the canonical JSON digest.
3. Transport order is not identity; the canonical encoding is injective over row values (tagged
   atoms, dates, decimals, tuples, escaped `"$"` maps), so type swaps cannot keep a digest.
4. Authority is `:NONE` in plans, results and receipts.
5. Live standing only when all stages are `:ontop` system-process observations.
6. Executor inputs are exact bytes: files are read once, hashed, and copied to a private snapshot
   the engine reads (TOCTOU closed); plans execute only against the catalog they bind to.
7. Receipts may be signed with a shared-key HMAC-SHA256 MAC; verification with `key:` refuses any
   edited or re-linked signed chain (`REFUSED_VKG_REPLAY`).

## Failure/refusal boundaries

All failures are `{:error, %AshR2RML.Refusal{}}`. Codes: 13 `REFUSED_VKG_*` plus
`REFUSED_RESOURCE_BOUND` and `REFUSED_OBDA_EXECUTION`, listed in `AshR2RML.Refusal.code()` and
`AGENTS.md`. Engines returning malformed shapes must refuse, not crash; malformed batch requests and non-map
result rows are refused or tolerated, never raised.

## Qualification court

`mix test test/vkg`, including `test/vkg/v26_9_28_docs_test.exs` (vocabulary closure). Live Ontop
execution requires Ontop and Postgres.

## Evidence boundary

Receipts prove observation of exact admitted sources under a plan, not correctness of source data,
not actuation, and not network-federation behavior.

## Authority law

No DO. Any contract or option requesting more than `:NONE` is `REFUSED_VKG_AUTHORITY_ESCALATION`.

## Closure

Closed: vocabulary, docs, packaging metadata, TOCTOU snapshotting, catalog-bound plan execution,
capability/ontology forwarding, injective digests, standing decode, optional shared-key MAC signing,
public verifying `Executor.replay/3`, inspection/batch/engineering hardening.

Residual: post-subject re-pin required; dialyzer not re-run by the docs stream. A shared-key MAC is
not a public-key signature: any verifier holding the key can forge, and without a key a fully
re-sealed session is self-consistent. The catalog is the admission trust root. The snapshot
protects engine inputs, not the database the engine queries.
