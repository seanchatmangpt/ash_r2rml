# AshR2ML documentation

AshR2ML maps ordinary Ash resources to a normalized semantic mapping IR and standards-valid W3C R2RML while leaving persistence to the active Ash data layer.

## Start here

- [Canonical Livebook](../ash_r2ml.livemd) — runnable end-to-end mental model.
- [Architecture](topics/architecture.md) — one-subject architecture, compiler layers, and boundaries.
- [Ash-first mapping](how_to/ash_first.livemd) — annotate an existing Ash/AshPostgres application.
- [Ontology-first generation](how_to/ontology_first.livemd) — RDF/OWL + SHACL + ggen → AshR2ML.
- [Relational schema and R2RML](how_to/managing_schema.livemd) — keep relational schema and semantic projection aligned.

## Reference

- [Support matrix](reference/support_matrix.md)
- [Usage rules index](../usage-rules.md)
- [Semantic mapping IR](../usage-rules/semantic-ir.md)
- [R2RML](../usage-rules/r2rml.md)
- [DSL](../usage-rules/dsl.md)
- [Semantic identities](../usage-rules/identities.md)
- [Relationships](../usage-rules/relationships.md)
- [Datatypes](../usage-rules/datatypes.md)
- [Custom Ash types](../usage-rules/custom-types.md)
- [Logical tables](../usage-rules/logical-tables.md)

## Integration

- [Query surfaces](../usage-rules/query-surfaces.md)
- [OBDA and virtual RDF](../usage-rules/obda.md)
- [Ontology-first rules](../usage-rules/ontology-first.md)
- [ggen manufacturing](../usage-rules/ggen.md)
- [Testing and semantic round trips](../usage-rules/testing.md)
- [Actions and mutation boundary](../usage-rules/actions.md)

## Project history

- [Migration from the AshNeo4j donor](topics/migration_from_ash_neo4j.md)
- [`CHANGELOG.md`](../CHANGELOG.md) preserves donor release history rather than rewriting historical Neo4j releases as AshR2ML releases.

## Product boundary

AshR2ML does not replace AshPostgres, implement a database driver, store triples, execute SPARQL, or require a graph database. Its job is deterministic semantic correspondence:

```text
Ash.Resource + RDF metadata
          ↓
   AshR2ML.Mapping
      ╱       ╲
relational    R2RML
   state        │
      ╲       OBDA
       ╲       ╱
      one subject
```
