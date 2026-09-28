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
2. Plan digest excludes filesystem paths.
3. Transport order is not identity; rows are normalized before digesting.
4. Authority is `:NONE` in plans, results and receipts.
5. Live standing only when all stages are system-process observations.

## Failure/refusal boundaries

All failures are `{:error, %AshR2RML.Refusal{}}`. Codes: 13 `REFUSED_VKG_*` plus
`REFUSED_RESOURCE_BOUND` and `REFUSED_OBDA_EXECUTION`, listed in `AshR2RML.Refusal.code()` and
`AGENTS.md`. Engines returning malformed shapes must refuse, not crash (tracked by other streams).

## Qualification court

`mix test test/vkg`, including `test/vkg/v26_9_28_docs_test.exs` (vocabulary closure). Live Ontop
execution requires Ontop and Postgres.

## Evidence boundary

Receipts prove observation of exact admitted sources under a plan, not correctness of source data,
not actuation, and not network-federation behavior.

## Authority law

No DO. Any contract or option requesting more than `:NONE` is `REFUSED_VKG_AUTHORITY_ESCALATION`.

## Closure

Closed: vocabulary, docs, packaging metadata. Residual: post-subject re-pin required; dialyzer not
re-run by the docs stream.
