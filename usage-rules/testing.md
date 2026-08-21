# Testing AshR2RML

AshR2RML testing is layered because different claims require different evidence.

## Unit tests

Pure mapping logic should be tested without external services:

- subject-template parsing;
- IRI validation;
- datatype registry lookups;
- normalized mapping IR construction;
- join-condition construction;
- deterministic ordering;
- typed refusal classification.

Unit tests are appropriate for pure functions and compile-time invariants.

## DSL compilation tests

Compile representative Ash resources and assert that `AshR2RML.Resource.Info.mapping/1` returns the expected normalized IR.

Fixtures should exercise:

- scalar attributes;
- required/optional attributes;
- semantic subject templates;
- `belongs_to`;
- `has_one`/`has_many`;
- many-to-many;
- association resources;
- composite identities;
- custom datatype mappings;
- named graphs where supported.

## R2RML conformance tests

Render Turtle and parse it using an independent RDF parser. Do not treat string matching alone as proof of valid R2RML syntax.

Tests should assert the intended R2RML structures:

```text
rr:TriplesMap
rr:logicalTable
rr:subjectMap
rr:predicateObjectMap
rr:objectMap
rr:parentTriplesMap
rr:joinCondition
```

## Determinism

Given identical admitted inputs, repeated compilation/rendering must produce byte-identical semantic artifacts unless a field is explicitly documented as nondeterministic receipt metadata.

Test deterministic ordering of resources, classes, predicate-object maps, joins, prefixes, and generated files.

## Relational integration

Use a real relational database for claims about relational correspondence. The canonical integration fixture uses AshPostgres/PostgreSQL.

Verify:

1. resources migrate successfully;
2. records written through Ash exist in the relational tables;
3. relationships are represented by the expected FK/join structure;
4. the same data is addressable by the generated R2RML mapping.

Mocks cannot prove this boundary.

## OBDA integration

The crown integration test runs a real compatible R2RML/OBDA engine against the same database and executes SPARQL.

For an admitted fixture:

```text
Ash write/read
     ↓
PostgreSQL
     ↓
generated R2RML
     ↓
real OBDA engine
     ↓
SPARQL
```

Compare normalized semantic IRIs, literal values, and relationships between Ash-visible state and SPARQL-visible virtual RDF.

## Ontology-first integration

The ontology-first suite adds the generation leg:

```text
RDF/OWL + SHACL
       ↓
      ggen
       ↓
generated Ash.Resource
       ↓
Postgres
       ↓
R2RML
       ↓
SPARQL
```

Tests must include invalid shapes proving fail-closed behavior before generated files are written.

## Required falsifiers

Maintain tests for:

- unsupported type does not become `xsd:string` silently;
- missing subject template field is refused;
- two distinct resources do not collide on subject IRI;
- relationship mappings are not silently dropped;
- ambiguous joins are refused;
- physical table/module rename does not alter semantic identity unless explicitly configured;
- predicate renames are explicit semantic changes;
- repeated ggen runs are deterministic;
- R2RML parses independently;
- SPARQL and Ash observe the same admitted subject.

## Standing

Use `PARTIAL_ALIVE` for successful lower checkpoints such as DSL compilation or Turtle parsing.

Use `ALIVE` only for the exact admitted end-to-end claim that actually executed, for example: "generic Person/Organization fixture persisted in PostgreSQL and queried through generated R2RML using a real OBDA engine with matching semantic identity and relationship results."
