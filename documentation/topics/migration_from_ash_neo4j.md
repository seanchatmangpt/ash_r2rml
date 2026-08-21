# From AshNeo4j donor code to AshR2RML

AshR2RML began from a fork of AshNeo4j. That ancestry matters for licensing, changelog history, and understanding which architectural patterns were reused, but it does not define the finished product.

## What was retained conceptually

The donor contained mature patterns worth preserving:

- Spark DSL construction;
- compile-time verifiers;
- resource introspection;
- normalized resource-mapping structures;
- relationship descriptors;
- typed error discipline;
- test fixtures around Ash resource semantics.

AshR2RML adapts those patterns toward standards-based semantic mapping.

## What was replaced

The finished product does not use Neo4j as its persistence target.

The conceptual substitutions are:

| AshNeo4j donor concept | AshR2RML finished concept |
|---|---|
| Neo4j node label | RDF class IRI |
| Neo4j property mapping | RDF predicate/object mapping |
| Neo4j edge descriptor | R2RML reference object map |
| node identifier | semantic subject map |
| Cypher rendering | R2RML rendering |
| Bolty connection | no AshR2RML database connection |
| Neo4j `Ash.DataLayer` | consumer's existing Ash data layer |
| graph persistence | virtual RDF over relational persistence |
| graph query execution | external OBDA/SPARQL execution |

## Why the changelog still mentions AshNeo4j

`CHANGELOG.md` preserves the repository's historical donor releases. Those entries are historical evidence and are not rewritten as though they were AshR2RML releases.

The AshR2RML release line begins only when the package/runtime implementation actually changes identity and is released under the AshR2RML contract.

## Compatibility tombstones

Some donor-era documentation paths remain as small compatibility files so existing links fail informatively instead of presenting stale Cypher/Neo4j behavior. They are not active features.

Examples include legacy filenames for atomics, traversal, spatial, vector, and Cypher-fragment rules.

## Migration criterion

The fork-to-product migration is complete when:

- public package/module metadata identifies AshR2RML;
- no public runtime API requires Neo4j/Bolty/Cypher;
- the generic semantic mapping IR is canonical;
- R2RML rendering and verifiers are complete;
- AshPostgres/PostgreSQL + real OBDA integration proves virtual RDF;
- ontology-first ggen generation passes its round-trip corpus;
- donor-specific runtime code is removed or explicitly isolated as a non-core optional adapter.

Until those criteria are executable, the documentation is a working-backwards product contract rather than evidence that every current donor implementation path has already been replaced.
