<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# Virtual Knowledge Graph (VKG)

`AshR2RML.VKG` is an **observe-only** exact-source federation layer over Ontop-backed views.

## Authority ceiling

- Observe-only. Authority is always `:NONE`; results and receipts carry standing `:observed_not_actuated` only for a genuine `AshR2RML.VKG.Engine.Ontop` system-process run (observation standing `:obda_query_observed`); every other engine, injected runner or test double yields `:test_double_only`. Standing is bound into the result digest, `Receipt.standing` is derived from the result and checked against it, and a per-observation evidence digest (evidence kind, standing, system, output digest, duration) is bound into the receipt.
- No DO: VKG never writes to a source, never actuates, and refuses any contract requesting more authority (`REFUSED_VKG_AUTHORITY_ESCALATION`).
- Not network federation: there is no cluster, gateway or remote-source protocol. Sources are named, exact-identity descriptors executed through the Ontop adapter.
- Not `AshR2RML.Federation`: that module is the in-process artifact-determinism substrate. Do not conflate or merge the two.

## Pipeline

```text
priv/vkg manifest -> admitted Catalog -> QueryPlan -> Executor (bounded)
  -> Result (Provenance) -> Receipt -> Replay verification
```

1. `AshR2RML.VKG.Manifest` loads source descriptors and manufactures digests from exact mapping/query bytes at load time. Never hand-copy digests.
2. `AshR2RML.VKG.Catalog` admits contracts (`Contract`, `SourceIdentity`, `Compatibility`) or refuses.
3. `AshR2RML.VKG.Planner` produces a deterministic `QueryPlan`; filesystem paths are excluded from the plan digest.
4. `AshR2RML.VKG.Executor` runs each stage through an engine (default `AshR2RML.VKG.Engine.Ontop`). Any refused stage refuses the whole query; partial results are never returned as the federation.
5. `AshR2RML.VKG.Result` / `Receipt` seal the observation; `Replay` and `Receipt.verify` recompute digests, trusting no stored value. Result rows are normalized to JSON-native values (atoms, dates, decimals become strings; tuples become lists) before sealing, and `Result.verify/1` refuses rows not in that form. Stage capabilities must stay inside the observe-only allowlist, and non-module or raising engines yield `REFUSED_VKG_EXECUTION`. Residual: with no signatures, a fully re-sealed session (consistent receipt, result and observations) is self-consistent by construction.

Entry points: `AshR2RML.VKG.query/2`, `query_all/1`, `catalog/1`. Consumers: `VKG.Consumer.Graphql`, `VKG.Consumer.Engineering`. `VKG.Batch` bounds request size.

## priv/vkg layout

`sources/*.json` (descriptor), `mappings/*.r2rml.ttl`, `contracts/*.ttl`, `queries/*.rq`, `shapes/federation-contract.shacl.ttl`, `ontology/vkg.ttl`.

## Determinism law

Same admitted catalog + same options + same observed rows (in any transport order) yield the same plan sha, result sha and receipt id. Engine byte order is not semantic identity. A result may claim live observation only if every stage was observed by a real system process; injected evidence weakens the whole result.

## Refusals

Every failure is `{:error, %AshR2RML.Refusal{}}` with a `REFUSED_VKG_*` code (plus `REFUSED_RESOURCE_BOUND` for size bounds). The full vocabulary is in `AGENTS.md`. New codes must be added to `AshR2RML.Refusal.code()` and `AGENTS.md`; `test/vkg/v26_9_28_docs_test.exs` enforces this.

## Testing

Use real fixtures from `priv/vkg` and `test/support/vkg_case.ex`. Fake engines are only for probing engine-returned shapes; no mocks otherwise.
