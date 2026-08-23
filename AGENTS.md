<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# AshR2RML Agent Operating Contract

This contract governs the repository unless a deeper `AGENTS.md` narrows a subtree. Live tree evidence outranks stale prose. Nested doctrine may tighten constraints but may not silently weaken evidence, semantic correspondence, authority, replay, or publication law.

## Product invariant

AshR2RML is the W3C R2RML/RDF semantic-mapping and DfCM type-compiler layer for Ash Framework. It is **not** an `Ash.DataLayer`, graph database, triplestore, proprietary query engine, or replacement persistence layer.

Ash resource metadata, explicit semantic annotations, and ontology-first profiles must normalize into one deterministic mapping IR before verification/rendering. Ash-first and ontology-first workflows must converge on the same admitted semantic subject.

Ownership remains explicit: Ash owns resource/action/domain semantics; relational data layers own persistence; AshR2RML owns semantic metadata, introspection, compile-time validation, normalized IR, R2RML rendering, and semantic type compilation; Ontop/OBDA owns virtual graph projection and SPARQL→SQL rewriting; Ash.Reactor owns saga/DAG execution and rollback; OCEL telemetry owns event-stream/trace reconstruction. Do not blur these boundaries.

## Preserve → Fence → Calculus

Resolve repo/ref/base to an exact commit and read applicable root+nested doctrine, README/docs, `mix.exs`, lockfile, CI, release workflow, generators, and test layout. Preserve public DSL/API, normalized IR, semantic identity, datatype law, correspondence, typed refusals, generated/manual ownership, and reversible alternatives. Apply Chesterton's fence before removing an existing boundary. One failed edge is topology, not graph failure.

`A = μ(O*)`; `R = receipt(A)`. Separate `SELECT`, `CONSTRUCT`, `DO`. Model/planner/generator/proof/hook output has no ambient execution authority. Hooks manufacture intents, never actuate. Consequential execution uses the repository's admitted Ash/Reactor/runtime boundary and must be receipted.

## Evidence / standing

Use `UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED | BUILD_BROKEN | UNSUPPORTED` plus typed `REFUSED_*`. `ALIVE` requires observed execution against the exact admitted subject. Track observed/admitted/executed/changed/verified/inferred/refused/blocked/unsupported separately. Inspection is not execution; compile metadata is not an executed mapping; emitted Turtle is not proven semantic equivalence; a workflow is not a successful run.

## Semantic correspondence law

Preserve the same admitted class, attribute/property, relationship/join, subject identity, datatype, cardinality, and graph semantics across Ash, relational, IR, R2RML, SHACL/profile, and OBDA projections. Normalize to IR first, verify second, render third. Never generate R2RML directly from scattered ad-hoc inspection paths.

Database identity and RDF identity are distinct. Subject templates/columns/constants/blank nodes must be explicit; every template field resolves to a mapped attribute; reference joins target stable unique identities. Never derive semantic IRIs silently from module names or internal row IDs.

Datatype conversion must be explicit and lossless. Unknown Ash types must not silently degrade to strings. Preserve typed semantic refusals for invalid IRIs, missing subject maps, non-unique identity, unmapped datatypes, ambiguous relationships, invalid joins, missing predicates/identity, unproven equivalence, invalid semantic types, type/Ash mismatch, projection requirements, and failed semantic round trips. Compile-time DSL violations fail at compile time; runtime APIs return the repository's typed refusal structure.

## Reactor / generated surfaces

Preserve native Ash.Reactor step contracts, dependency order/concurrency semantics, middleware telemetry, and strict reverse rollback where the live implementation requires them. Generated artifacts are projections: edit their owning ontology/profile/IR/schema/template/generator rather than hand-editing outputs.

## Work / verification

Follow `parse → orient → resolve → materialize → read doctrine → inspect → admit/refuse → diagnose/repair → construct → actuate → receipt → replay → standing`. Prefer the existing lawful path and smallest coherent diff. No fabricated evidence, weakened tests, acceptance mocks for real DB/OBDA/Reactor claims, unrelated refactors, or unresolved production placeholders.

Acceptance precedence: exact user behavior/command → live documented repository command → narrowest equivalent. Discover the current ladder from `mix.exs`, tests, CI, and release workflow at the admitted SHA rather than freezing it here. Preserve the intended progression across formatting/compilation, pure IR tests, adversarial/refusal tests, enterprise/policy cases, live OBDA integration, Reactor rollback, package build, and release gates when those surfaces exist. CI supplements local execution; it is not truth.

## GitHub / receipt

Never silently move the admitted base. Unless explicitly instructed otherwise: purpose branch, intentional commit, non-force push, draft PR, no merge. Final receipt identifies repo/base/tree, O/O*, transports/failures, changed/generated surfaces, commands/exits, verification ladder, receipt/replay, branch/SHA/PR, semantic standing, and falsifiers.