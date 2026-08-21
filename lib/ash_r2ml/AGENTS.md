# AGENTS.md — AshR2ml side-by-side semantic projection

This subtree is governed by the root `AGENTS.md` plus the following migration rules.

## Purpose

`AshR2ml` is an additive W3C R2RML/SHACL semantic compiler for Ash resources. It is not a replacement data layer in this phase. Existing `AshNeo4j.DataLayer`, future `AshPostgres.DataLayer`, and any other storage implementation retain persistence and transaction authority.

## DfCM migration law

Preserve both lawful worlds until behavioral equivalence is observed:

1. Keep existing Neo4j/Bolt/Cypher implementation and tests intact as a control path.
2. Add R2RML metadata beside existing resource configuration.
3. Compile metadata into a canonical mapping IR before rendering any external representation.
4. Generate deterministic R2RML and SHACL projections from that IR.
5. Expand relationship dependencies to closure; never silently omit an unmapped destination.
6. Treat successful projection as `PARTIAL_ALIVE`, not cutover readiness.
7. Require observed SPARQL-to-SQL behavioral parity against the same admitted subject before any cutover may be proposed.
8. Cutover is a separate authorized actuation. Mapping generation must never remove or disable the control path.

## Authority boundary

The semantic compiler is SELECT/CONSTRUCT only. It may describe a relational subject and manufacture mapping artifacts. It must not create, update, or delete application rows, graph nodes, database schema, or production endpoints.

## Standards boundary

Use W3C terms precisely:

- R2RML namespace: `http://www.w3.org/ns/r2rml#`
- SHACL namespace: `http://www.w3.org/ns/shacl#`
- R2RML logical tables are exactly one of `rr:tableName` or `rr:sqlQuery`.
- Ash relationships become R2RML referencing object maps using the Ash relationship's source and destination attributes as join columns.
- Subject templates must include all primary-key columns so identity manufacture is deterministic.

## Extension rules

- Do not make `AshR2ml` an `Ash.DataLayer` while the side-by-side experiment is active.
- Do not add a triplestore as an authoritative copy of application state.
- Do not hand-maintain an RDF graph synchronized from the database.
- Do not add SPARQL execution authority to a renderer.
- Fail closed when a relationship destination lacks an R2RML mapping.
- Prefer data-layer-neutral Ash metadata; use relational column `source` names when present.

## Verification ladder

Run, in order:

1. `mix compile --force --warnings-as-errors`
2. `mix test test/ash_r2ml_test.exs`
3. `mix test`
4. full CI matrix from `.github/workflows/ci.yaml`
5. later OBDA integration: execute paired SQL/SPARQL queries against the exact same Postgres fixture and compare normalized result multisets

Only step 5 can upgrade `query_parity` from `UNKNOWN` to `VERIFIED`.
