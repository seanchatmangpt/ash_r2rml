# Logical tables

R2RML maps RDF subjects and properties over a logical relational source. AshR2RML derives that source from the active relational data-layer configuration whenever possible.

## Table-backed resources

For ordinary AshPostgres resources, prefer `rr:tableName` based on the configured PostgreSQL table.

The physical table name is not RDF identity. Renaming a table must not change subject IRIs unless the subject map explicitly includes that physical value.

## Views

Database views are valid logical sources when the Ash resource is intentionally mapped to them and the resulting mapping remains deterministic.

Views are useful for relational projections that are stable, typed, and already part of the application's data model. Do not create views solely to hide a semantic modeling error in the Ash resource graph.

## SQL-query logical tables

Explicit `rr:sqlQuery` mappings are advanced and read-only from AshR2RML's perspective. They require:

- deterministic SQL;
- explicit column contract;
- no ambient mutation authority;
- test coverage proving the projected columns and identities;
- compatibility with the configured OBDA engine.

## Data-layer boundary

AshR2RML does not generate or execute migrations merely because it knows the desired RDF mapping. Persistence/schema lifecycle stays with the active Ash data layer and its migration tooling.

## Drift

Tests should detect when the logical table or referenced columns no longer exist in the relational schema. A syntactically valid R2RML file pointing at stale columns is not a valid application mapping.
