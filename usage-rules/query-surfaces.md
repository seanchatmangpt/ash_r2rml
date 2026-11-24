# Query surfaces

AshR2RML enables multiple query surfaces over one persisted relational subject.

## Ash

Ash queries remain the application-native interface for loading resources, relationships, calculations, aggregates, authorization-aware reads, and actions.

AshR2RML does not intercept ordinary Ash query execution.

## SQL

The relational database remains directly queryable with SQL for operations, analytics, migrations, and database-native tooling.

## SPARQL

SPARQL is executed by `AshR2RML.OBDA.InMemory.query/4` (or `query_many/3`) over a graph materialized from a real `Ash.read/2`. Actor, tenant, and `authorize?` (default `true`) apply. No SQL-rewriting engine is shipped.

```text
Ash query ───────────────────┐
SQL query ───────────────────┼──► same persisted subject
SPARQL → InMemory → Ash.read ┘
```

## Semantic equivalence

The three query surfaces do not need identical syntax or feature sets. They must agree on the admitted semantic facts they claim to expose: subject identity, mapped scalar values, and mapped relationships.

## Ash calculations and aggregates

Calculated values are mapped to RDF only when there is an explicit stable relational/logical-table projection for them. An in-memory Ash calculation is not automatically a relational R2RML column.

Do not pretend a runtime-only calculation is available to SPARQL unless an explicit SQL/view mapping makes that statement true.

## Query combinations

Union/intersection/other Ash query features remain Ash/data-layer concerns. They do not require special R2RML syntax merely because the application can express them.

R2RML describes the virtual graph; SPARQL algebra is handled by the InMemory backend's SPARQL engine.

## Verification

When a feature is claimed across Ash and SPARQL, test both against the same fixture and compare semantic results rather than implementation-level row ordering or internal IDs.
