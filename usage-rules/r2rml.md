# R2RML

AshR2ML renders the normalized mapping IR as W3C R2RML Turtle.

## Mapping model

Each mapped Ash resource becomes an `rr:TriplesMap` with:

- `rr:logicalTable` derived from the active relational data-layer mapping;
- `rr:subjectMap` derived from the semantic identity contract;
- zero or more `rr:class` values;
- scalar `rr:predicateObjectMap` entries;
- relationship mappings using `rr:RefObjectMap` and `rr:joinCondition` where required.

## Deterministic rendering

Rendering must be deterministic for the same normalized IR. Sort resources and child mapping structures by stable semantic keys before serialization.

Prefix selection must not change the meaning of the graph. Prefixes are presentation; absolute IRIs are semantic identity.

## Scalar properties

A scalar property mapping must preserve:

```text
Ash attribute
RDF predicate
relational source column/expression
RDF datatype or term type
```

Do not emit an object map whose datatype is only a guess.

## Reference object maps

Relationships use parent triples maps and join conditions. The target parent map must exist in the same compiled mapping set or be explicitly admitted as an external mapping target.

Do not create a reference object map to an unidentified parent resource.

## Logical tables

Ordinary table-backed resources should use `rr:tableName`. SQL-query logical tables are permitted only through an explicit read-only mapping surface and must be deterministic.

## Graph maps

Named graphs are optional. When absent, mappings target the default graph. Graph maps do not change the underlying relational persistence model.

## Validation

Generated Turtle must be parsed by an independent RDF parser in the test suite. The conformance suite must additionally inspect required R2RML vocabulary usage and run at least one real OBDA integration.

## Non-goals

AshR2ML does not:

- materialize triples as its persistence strategy;
- implement SPARQL execution;
- perform arbitrary OWL reasoning;
- claim that an R2RML mapping enforces all SHACL constraints.
