# PRD v26.9.28 — VKG-001: Observe-only Virtual Knowledge Graph Federation

**Status:** IMPLEMENTED with named residual risks (see "Closed vs residual")
**Implementation standing:** PARTIAL_ALIVE — landed in `d61c0db`; integrity-closure work is post-subject
**Release:** v26.9.28
**Repository:** `seanchatmangpt/ash_r2rml`
**Owner:** ash_r2rml
**Dependencies:** `AshR2RML.OBDA` Ontop adapter, `AshR2RML.Refusal`, R2RML rendering
**Authority ceiling:** observe-only (`authority: :NONE`); no DO; not network federation; not `AshR2RML.Federation`

## Product outcome

A caller can query one or more admitted, exact-source virtual graph contracts and receive a
provenance-bearing result plus a receipt that a third party can replay-verify, or a typed refusal.

## Problem

Ontop-backed views need federation-style access without turning observation into authority or
trusting stale hand-copied digests.

## Functional requirements

1. Load source descriptors from `priv/vkg` and manufacture mapping/query digests from exact bytes.
2. Admit contracts (identity, shape, compatibility, authority) or refuse with `REFUSED_VKG_*`.
3. Produce a deterministic `QueryPlan`; identical inputs give identical plan sha.
4. Execute stages through an engine with row/time bounds; any refused stage refuses the whole query.
5. Seal a `Result` with per-row provenance and a `Receipt` chained by `previous`.
6. Verify receipts and replay by recomputing digests; trust no stored digest.
7. Refuse any authority above `:NONE`.
8. Every failure is `{:error, %AshR2RML.Refusal{}}` with a code in `Refusal.code()` and `AGENTS.md`.

## Acceptance criteria

1. `AshR2RML.VKG.query_all/1` over `priv/vkg` yields a sealed session whose receipt verifies.
2. Tampering with a plan, result or receipt is refused on verify/replay.
3. Source drift refuses with `REFUSED_VKG_SOURCE_DRIFT`.
4. Row-order permutation of engine output does not change result identity.
5. Every `REFUSED_*` atom in `lib/ash_r2rml/vkg` is in `Refusal.code()` and documented in `AGENTS.md` (closure test).

## Non-goals

- Writing to sources or any DO/actuation.
- Network federation, remote source protocols, multi-tenant deployment.
- Replacing `AshR2RML.Federation` or the Ontop engine; SPARQL-to-SQL rewriting stays in Ontop.

## Evidence product

Content-addressed `Receipt` (plan, catalog, result, per-contract observation digests, standing
`:observed_not_actuated`). Live standing requires every stage observed by a real system process.
Source presence or prose is not standing.

## Non-functional requirements

- Deterministic identity for identical admitted inputs; typed refusals; no ambient authority.
- Bounded rows and request size (`REFUSED_RESOURCE_BOUND`).
- Exact-head subject fencing.

## Closed vs residual

Closed in the integrity pass: refusal vocabulary in `Refusal.code()`/`AGENTS.md` with a closure test
(read through `Code.Typespec`, independent of the type's source layout); usage-rules, README, AGENTS,
PRD/ARD docs; docs module group; package files.

Closed in the residual-risk pass (`test/vkg/v26_9_28_residual_test.exs`):

- TOCTOU: the executor snapshots mapping/query/ontology bytes once, hashes the bytes, and runs the
  engine on private snapshot paths, so a file swapped after hashing never reaches the engine.
- Hand-built plans: execution re-resolves every stage against the bound catalog (the plan's own or a
  supplied `:catalog`); arbitrary paths/digests are refused (`REFUSED_VKG_QUERY_PLAN` /
  `REFUSED_VKG_SOURCE_DRIFT`), and plans with no binding are refused.
- Requested capability is forwarded to Ontop as `required_capabilities`; stage ontology digests are
  all-or-none.
- Plan and observation digests use the injective canonical JSON encoding, not `term_to_binary`.
- `decode_receipt` accepts every standing the code can emit (single source: `Result.standings/0`).
- Optional receipt signing: `Receipt.sign/2` (shared-key HMAC-SHA256 MAC) with `key:` /
  `require_signature:` verification. It proves key-holder endorsement of an exact receipt, not
  public-key authenticity, non-repudiation, freshness, or that the engine ran.
- `Executor.replay/3` is public and verifies recorded evidence instead of trusting it.
- `Inspection.snapshot` surfaces `ontology_sha256`; `Batch` and `Consumer.Engineering.snapshot`
  refuse or tolerate malformed input instead of raising.

Residual (not closable in this repository): live Ontop execution needs Ontop and Postgres and is not
exercised by these tests; with no key, or with a key the attacker also holds, a fully re-sealed
session is self-consistent by construction (a shared-key MAC is not a public-key signature); the
bound catalog is trusted as the admission root, so callers should supply their own `:catalog` for
plans they did not build; the snapshot protects the engine input, not the database the engine
queries; a hostile local user who can write inside the private temp directory as the same OS user is
out of scope. **The release workflow subject is frozen at `40d181f`; these changes are post-subject
and need a re-pin or the next release to ship.**

## Definition of done

Observe-only VKG queries are admitted, bounded, sealed, replay-verifiable or typed-refused, with the
authority ceiling and refusal vocabulary documented and mechanically checked.
