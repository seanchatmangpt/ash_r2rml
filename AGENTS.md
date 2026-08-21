<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# AGENTS.md — AshR2RML

This repository is the generic semantic mapping layer between Ash resources and W3C R2RML.

The historical codebase was forked from AshNeo4j. Treat that implementation as donor material, not as the product definition. The public contract is AshR2RML.

## Product invariant

AshR2RML is **not** an `Ash.DataLayer`, graph database, triplestore, SPARQL engine, or application ontology.

AshR2RML compiles Ash resource metadata plus explicit semantic annotations into a normalized mapping IR and standards-valid R2RML. Existing Ash data layers continue to own persistence.

```text
Ash.Resource + semantic metadata
             │
             ▼
      AshR2RML.Mapping
         ╱         ╲
        ▼           ▼
 relational DB     R2RML
        │           │
        └─────┬─────┘
              ▼
       ONE SUBJECT
       Ash / SQL / SPARQL
```

For ontology-first generation:

```text
RDF/OWL
   ↓
application profile
   ↓
SHACL operational shapes
   ↓
ggen
   ↓
generated Ash.Resource
   ↓
AshR2RML.Mapping
   ↓
R2RML
```

Both Ash-first and ontology-first workflows must converge on the same mapping IR.

## Architectural ownership

Keep boundaries explicit:

- **Ash** owns resource/action/domain semantics.
- **AshPostgres or another Ash data layer** owns persistence.
- **Ecto/AshPostgres migration machinery** owns relational DDL where applicable.
- **AshR2RML** owns semantic mapping metadata, introspection, validation, normalized mapping IR, and R2RML rendering.
- **ggen** is the development/manufacturing path for ontology-first Ash and generated compiler surfaces; it is not automatically a runtime dependency.
- **SHACL** supplies operational closure for ontology-first generation.
- **An OBDA/R2RML engine** owns SPARQL-to-SQL rewriting and virtual RDF execution.

Do not move responsibilities across those boundaries merely to make a test pass.

## Core semantic correspondence

The implementation must preserve these correspondences:

| Semantic construct | Ash projection | Relational projection | R2RML projection |
|---|---|---|---|
| RDF/OWL class | resource | table/view | `rr:class` |
| datatype property | attribute | column/expression | predicate-object map |
| object property | relationship | FK/join/association | reference object map |
| semantic identity | subject mapping / Ash identity | stable unique key(s) | subject map |
| datatype | Ash type | storage type | `rr:datatype` |
| required scalar | `allow_nil? false` | `NOT NULL` where lawful | object map + shape constraint |
| to-one relationship | `belongs_to`/`has_one` | FK | `rr:RefObjectMap` |
| many-valued relationship | `has_many`/`many_to_many` | FK/join table | repeated/reference maps |

A mapping is correct only if the same admitted relationship or value survives across all relevant projections.

## Normalized mapping IR

All public compilation paths must converge on a deterministic, inspectable IR. The canonical concepts are:

```text
AshR2RML.Mapping.Resource
AshR2RML.Mapping.SubjectMap
AshR2RML.Mapping.PredicateObjectMap
AshR2RML.Mapping.ReferenceObjectMap
AshR2RML.Mapping.JoinCondition
AshR2RML.Mapping.Datatype
AshR2RML.Mapping.GraphMap
```

Names may evolve only if the replacement is demonstrably clearer and the public docs/tests are changed in the same PR.

Do not generate R2RML directly from ad-hoc resource inspection in multiple unrelated code paths. Normalize first, render second.

## Resource DSL

The public DSL should expose only semantic information Ash cannot lawfully infer.

Resource-level concepts include:

```elixir
r2rml do
  class "https://schema.org/Person"

  subject do
    template "https://example.org/people/{id}"
    term_type :iri
  end
end
```

Attributes may add RDF predicate/datatype metadata:

```elixir
attribute :name, :string do
  rdf do
    predicate "http://xmlns.com/foaf/0.1/name"
  end
end
```

Relationships may add object-property metadata:

```elixir
belongs_to :organization, Organization do
  rdf do
    predicate "https://schema.org/memberOf"
  end
end
```

Do not require users to duplicate source/destination attributes, relationship destinations, table names, or datatypes when Ash/data-layer introspection already proves them.

## Semantic identity

Database identity and RDF identity are distinct.

Subject mappings may be based on:

- IRI templates;
- columns/attributes;
- constant IRIs;
- blank nodes only when explicitly admitted.

Every template field must resolve to a real mapped attribute. Joins used by reference object maps must target a stable identity. Mapping identity must not depend accidentally on a database-generated key unless the subject contract explicitly says so.

Never silently create an RDF IRI from an Elixir module name.

## Datatype law

Datatype conversion must be explicit and loss-aware.

Built-in mappings should cover common Ash scalar types. Custom types need an explicit AshR2RML datatype contract/registry entry.

Never implement a fallback of:

```text
unknown Ash type → string
```

If no lawful RDF lexical/datatype representation is known, return a typed unsupported/refusal result.

## Relationship law

An Ash relationship carrying an RDF predicate is a semantic edge. It must never disappear silently during R2RML compilation.

For a relational data layer, derive lawful `rr:RefObjectMap` joins from Ash relationship/data-layer metadata. If the source/destination identity or join cannot be proven, refuse the mapping.

Do not serialize relationships into JSON or scalar strings merely to avoid modeling a join.

Association resources are first-class when the relation itself carries identity, attributes, provenance, temporal validity, or other semantics.

## Ontology-first law

Do not compile arbitrary OWL directly into a relational schema.

Use:

```text
public/application ontology
        ↓
application profile
        ↓
SHACL operational shape
        ↓
ggen compilation
```

OWL/RDFS provides semantics; SHACL/profile facts provide the closed operational information required for Ash/relational manufacture.

When multiple relational/Ash projections remain lawful after reading the shape, preserve the alternatives until constraints select one. If no deterministic choice exists, refuse.

Do not invent `owl:equivalentClass` or `owl:equivalentProperty`. Equivalence requires evidence. Weaker mappings must remain weaker mappings.

## ggen law

Use ggen for deterministic manufacture, not as a hidden pile of shell transforms.

The ontology-first pack should follow the normal ggen shape:

```text
ontology.ttl
application profile / shapes
queries/*.rq
gates/*.rq
templates/*
ggen.toml
```

Generation must fail closed before writing artifacts when required semantic facts are absent or contradictory.

Generated Ash/R2RML/compiler surfaces are projections. Never fix them by hand when an ontology, shape, query, template, or generator owns them.

Run generation twice and require deterministic output except for explicitly declared receipt metadata.

## Typed refusals

Prefer typed semantic failures to silent fallback. Representative refusal classes include:

```text
REFUSED_INVALID_CLASS_IRI
REFUSED_MISSING_SUBJECT_MAP
REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY
REFUSED_UNMAPPED_DATATYPE
REFUSED_AMBIGUOUS_RELATIONSHIP
REFUSED_INVALID_JOIN_CONDITION
REFUSED_RELATIONSHIP_WITHOUT_PREDICATE
REFUSED_R2RML_JOIN_WITHOUT_IDENTITY
REFUSED_UNPROVEN_EQUIVALENCE
UNSUPPORTED_TERM_TYPE
UNSUPPORTED_ASH_TYPE
```

Exact Elixir names may differ, but the semantic distinctions must remain inspectable.

Compile-time DSL/schema violations should fail at compile time. Runtime rendering APIs should return typed errors instead of raising for expected unsupported input.

## Donor-code classification

Before changing inherited AshNeo4j code, classify it:

- `PRESERVE`: generally useful Ash/Spark/error/testing architecture.
- `ADAPT`: reusable concept with Neo4j-specific vocabulary or assumptions.
- `TEMPORARILY_KEEP`: needed only while extracting/validating replacement behavior.
- `REMOVE`: Neo4j/Cypher/Bolty-specific implementation that has no role in finished AshR2RML.
- `UNSUPPORTED`: behavior intentionally outside the product.

Expected direction:

| Donor surface | Direction |
|---|---|
| Spark DSL patterns | preserve/adapt |
| resource introspection | preserve/adapt |
| `ResourceMapping` idea | adapt into R2RML IR |
| edge descriptor idea | adapt into reference-object mapping |
| verifiers | preserve/expand |
| typed errors | preserve/rename |
| Cypher renderer | remove |
| Bolty | remove |
| Neo4j `Ash.DataLayer` | remove |
| Neo4j sandbox | remove |
| Neo4j spatial/vector/index helpers | remove unless independently useful to generic mapping |
| label/world resolution | remove or replace with RDF class/semantic mapping concepts only where required |

Do not mass-delete donor code before its useful architecture and tests have been understood.

## Development sequence

For substantial implementation work, proceed in this order unless evidence requires a different dependency order:

1. Establish exact base SHA and baseline tests.
2. Introduce the generic `AshR2RML.Mapping` IR with pure unit tests.
3. Adapt Spark DSL and resource introspection to compile into that IR.
4. Implement deterministic standards-valid R2RML rendering.
5. Add datatype, identity, relationship, join, graph-map, and logical-table verifiers.
6. Add generic Ash-first fixtures.
7. Add ggen ontology/SHACL manufacturing pack and fail-closed gates.
8. Add generated ontology-first fixture resources.
9. Add real relational integration, normally with AshPostgres/PostgreSQL.
10. Add a real R2RML/OBDA integration proving SPARQL sees the same persisted subject.
11. Remove Neo4j/Bolty/Cypher donor infrastructure only after replacement coverage proves it is no longer needed.
12. Update package metadata/docs/release surfaces and run the full release gate.

## Verification ladder

Use the cheapest high-information verifier first:

1. format/syntax;
2. mapping IR unit tests;
3. DSL/introspection tests;
4. R2RML rendering tests;
5. parse generated Turtle with a standards-compliant RDF parser;
6. deterministic render/regeneration checks;
7. generic Ash fixture tests;
8. relational integration tests;
9. real R2RML/OBDA query tests;
10. ontology-first ggen round trip;
11. full suite / release checks.

A unit test cannot prove an external database, RDF parser, ggen executable, or OBDA engine boundary.

## Required semantic falsifiers

Maintain permanent tests for at least:

- datatype drift;
- subject/IRI identity collision;
- missing template field;
- relationship loss;
- invalid/ambiguous join condition;
- cardinality/storage mismatch where ontology-first generation is involved;
- predicate drift after Elixir field rename;
- physical table rename changing RDF identity unexpectedly;
- accidental equivalence inflation;
- unsupported custom type silently becoming a string;
- generation nondeterminism;
- SPARQL result disagreeing with the same Ash-visible relational subject.

## Definition of done

The repository is not done when it compiles or when the DSL renders a Turtle string.

### Semantic core done

- `AshR2RML.Mapping` is the single normalized IR.
- Resource, subject, scalar property, relationship, join, datatype, identity, and graph mappings are represented.
- Spark DSL/introspection deterministically compile Ash resources into the IR.
- Unsupported or ambiguous mappings are typed failures.

### R2RML done

- IR renders standards-valid W3C R2RML Turtle.
- Scalars generate lawful predicate-object maps.
- relationships generate lawful reference object maps and joins.
- semantic identities generate stable subject maps.
- generated Turtle parses with an independent RDF parser.

### Ontology-first done

- a shipped ggen pack compiles a generic RDF/SHACL application profile into ordinary Ash resources carrying AshR2RML metadata;
- shapes cover scalar, to-one, to-many, association-resource, identity, and datatype cases;
- ambiguous/open-world shapes fail closed;
- two identical ggen runs produce identical generated projections.

### Relational/OBDA crown done

A generic fixture proves:

```text
RDF/SHACL (for ontology-first fixture)
        ↓
       ggen
        ↓
     Ash.Resource
        ↓
 relational persistence
        ↓
 generated R2RML
        ↓
 real OBDA engine
        ↓
      SPARQL
```

The semantic IRIs, scalar values, and required relationships returned by SPARQL match the same subject observed through Ash.

This is `ALIVE` only for the admitted fixture/query fragment actually executed.

### Fork migration done

- package/module/public docs describe AshR2RML, not AshNeo4j;
- Neo4j, Bolty, Cypher, Neo4j schema/index/sandbox functionality is removed from the target runtime unless explicitly retained as an optional independently justified adapter;
- no public API requires a graph database;
- no hidden donor terminology remains in public docs or package metadata except historical changelog/license attribution;
- release/test/docs tooling targets AshR2RML.

## Standing vocabulary

Use:

- `UNKNOWN`
- `PARTIAL_ALIVE`
- `ALIVE`
- `BLOCKED`
- `BUILD_BROKEN`
- `UNSUPPORTED`
- `REFUSED_<TYPE>`

Source presence, compilation, generated files, or a workflow definition do not by themselves establish `ALIVE`.

## Publication

For repository writes:

- branch from the exact admitted base;
- preserve unrelated work;
- use cohesive commits;
- open/update a draft PR unless explicitly told otherwise;
- do not merge without explicit authorization;
- inspect the exact published head and CI;
- report commands/evidence separately from inference.

Do not publish to Hex or create a release merely because implementation is complete. Release is a separate authorized act.

## Final receipt

Every implementation PR must report:

```text
OBSERVED
ADMITTED
CHANGED
GENERATED
EXECUTED
VERIFIED
INFERRED
REFUSED
BLOCKED
UNSUPPORTED
STANDING
```

Include exact base/head SHAs, branch/PR, changed surfaces, generator inputs/outputs, verification commands and exits, semantic round-trip evidence, unresolved falsifiers, and replay commands.

The receipt must let another operator reproduce the standing without trusting prose.
