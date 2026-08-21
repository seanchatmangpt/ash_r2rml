# OBDA and virtual RDF

AshR2RML stops at R2RML generation. A compatible Ontology-Based Data Access engine executes SPARQL by rewriting it into SQL over the relational database.

## Architecture

```text
SPARQL
   ↓
OBDA / R2RML engine
   ↓
SQL
   ↓
relational database
```

The database remains the authoritative operational state. The RDF graph is virtual unless an application deliberately materializes it elsewhere.

## One-subject invariant

Ash, SQL, and SPARQL must observe the same underlying persisted subject. There is no required dual-write path and no second authoritative graph store.

## Engine boundary

AshR2RML does not implement:

- SPARQL parsing;
- SPARQL algebra;
- query planning;
- SQL rewriting;
- RDF entailment engines.

Use an existing standards-capable OBDA/R2RML engine.

## Compatibility

The conformance suite should document which engine/version is used for crown integration. Engine-specific quirks belong in adapters/tests, not in the semantic IR.

Do not weaken R2RML semantics to satisfy one engine when the engine behavior is non-standard; isolate the compatibility issue and record it.

## Verification

A real OBDA test must:

1. start against a real relational fixture;
2. load the generated R2RML mapping;
3. execute SPARQL;
4. normalize results by semantic IRI and RDF term value;
5. compare them to the same subject observed through Ash.

A generated mapping file without query execution is `PARTIAL_ALIVE`, not the crown.
