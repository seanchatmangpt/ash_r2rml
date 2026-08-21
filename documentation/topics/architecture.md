<!--
SPDX-FileCopyrightText: 2026 ash_r2ml contributors

SPDX-License-Identifier: MIT
-->

# AshR2ML Architecture

AshR2ML is a semantic compilation layer between Ash's domain model and W3C R2RML. It does not replace the application's data layer and it does not execute SPARQL.

## The one-subject model

AshR2ML exists to preserve one operational subject across several query models:

```text
                   semantic model
                         │
                         ▼
                  AshR2ML.Mapping
                    ╱           ╲
                   ▼             ▼
             Ash.Resource       R2RML
                   │             │
                   ▼             ▼
             relational DB   virtual RDF
                   │             │
                   ├── SQL       └── SPARQL
                   └── Ash
```

The relational database is authoritative operational state. The RDF graph is a virtual semantic projection unless a downstream system explicitly materializes it.

The architecture therefore avoids:

- a second authoritative graph store,
- dual writes,
- asynchronous RDF synchronization,
- semantic drift between duplicated storage systems.

## Compiler boundaries

AshR2ML is intentionally split into five layers.

### 1. Ash introspection

The library observes an Ash resource and its normal data-layer metadata:

```text
resource module
domain
attributes
relationships
identities
data-layer source/table metadata
source/destination attributes
Ash types
nullability
```

This layer answers only facts Ash already knows.

### 2. Semantic DSL

The Spark extension supplies meaning Ash cannot infer:

```text
RDF class IRI
predicate IRI
subject construction
term type
graph map
explicit datatype override
semantic alignment metadata
```

The DSL should be sparse. Duplicating relational information here creates a drift surface.

### 3. Mapping IR

All mapping inputs compile to a normalized intermediate representation:

```text
AshR2ML.Mapping.Resource
AshR2ML.Mapping.SubjectMap
AshR2ML.Mapping.PredicateObjectMap
AshR2ML.Mapping.ReferenceObjectMap
AshR2ML.Mapping.JoinCondition
AshR2ML.Mapping.GraphMap
AshR2ML.Mapping.Datatype
```

This is the semantic center of the library.

R2RML rendering consumes the IR rather than repeatedly re-introspecting arbitrary resource structures. Verifiers also operate against the same normalized facts.

### 4. R2RML renderer

The renderer manufactures standards-valid Turtle using the W3C R2RML vocabulary.

Correspondence:

| Mapping IR | R2RML |
|---|---|
| resource | `rr:TriplesMap` |
| logical table | `rr:logicalTable` |
| subject map | `rr:subjectMap` |
| RDF class | `rr:class` |
| scalar property | `rr:predicateObjectMap` |
| RDF predicate | `rr:predicate` |
| relational column | `rr:column` |
| RDF datatype | `rr:datatype` |
| relationship | `rr:RefObjectMap` |
| destination resource | `rr:parentTriplesMap` |
| FK/key pair | `rr:joinCondition` |

### 5. OBDA runtime

SPARQL execution belongs to an external R2RML/OBDA implementation:

```text
SPARQL
   ↓
OBDA engine
   ↓
SQL
   ↓
relational database
```

AshR2ML generates and validates the mapping consumed by this engine. It does not implement query planning for SPARQL.

## AshR2ML is not a DataLayer

The storage boundary remains ordinary Ash:

```elixir
use Ash.Resource,
  domain: MyApp.Domain,
  data_layer: AshPostgres.DataLayer,
  extensions: [AshR2ML.Resource]
```

This separation is deliberate.

`AshPostgres` owns:

- relational persistence,
- SQL generation,
- transactions,
- migrations,
- database constraints,
- relational query execution.

`AshR2ML` owns:

- semantic mapping metadata,
- semantic identity construction,
- Ash-to-R2RML correspondence,
- mapping verification,
- R2RML rendering,
- ontology-first generation support.

## Identity

Ash identity and RDF subject identity are related but not identical.

A relational record may use a UUID primary key while exposing a semantic IRI based on several fields:

```text
Postgres identity:
  id = 7f4e...

RDF identity:
  https://example.org/accounts/acme/1234
```

The mapping IR therefore stores subject construction explicitly.

A subject map is valid only when every referenced field is known and the construction is deterministic for the admitted resource.

## Attributes

A mapped scalar attribute has two independent meanings:

```text
Ash attribute storage/value semantics
RDF predicate + RDF term semantics
```

AshR2ML derives storage metadata and type information where possible, then adds semantic metadata.

Example:

```text
Ash:
  :balance :: :decimal

Postgres:
  balance NUMERIC

RDF:
  ex:balance "104.20"^^xsd:decimal
```

Datatype translation is explicit. Unknown types are never converted to strings merely to make the mapping render.

## Relationships

Relationships are the key graph-relational correspondence.

Example:

```text
Person --memberOf--> Organization
```

may be represented relationally as:

```text
people.organization_id → organizations.id
```

and semantically as:

```text
<PersonIRI> schema:memberOf <OrganizationIRI>
```

The same Ash relationship drives both sides of the correspondence.

For a to-one relationship, AshR2ML derives the R2RML join from Ash relationship metadata.

For many-to-many relationships, the compiler follows the declared join relationship/resource.

If the relation itself carries facts, it should remain a first-class resource rather than being collapsed to a bare edge.

## Ontology-first manufacturing

AshR2ML supports ontology-first projects through ggen.

The public ontology is not edited to contain application storage details. The layers are:

```text
public ontology / domain ontology
             │
             ▼
application profile / alignments
             │
             ▼
SHACL operational shapes
             │
             ▼
           ggen
             │
             ▼
generated Ash + AshR2ML metadata
```

SHACL is the operational closure boundary because relational generation needs explicit decisions about cardinality, requiredness, datatype, and identity that open-world OWL alone may not provide.

## Combinatorial relational projection

An ontology relation may admit more than one physical representation before constraints are applied.

For example:

```text
Resource --taggedWith--> Concept
```

could become:

- a foreign key,
- a join table,
- an association resource,
- a derived view.

The ontology-first compiler should preserve the lawful candidate set until the application profile and SHACL constraints force a deterministic choice.

If multiple materially different projections remain valid, generation refuses with an ambiguous-mapping error.

It never silently selects the easiest representation.

## Mapping determinism

For the same admitted resource graph and configuration, the mapping IR and rendered R2RML must be stable.

Determinism covers:

- triples-map identity,
- class IRI ordering,
- predicate-object-map ordering,
- join conditions,
- datatype mappings,
- rendered Turtle structure.

Deterministic output makes generated mappings reviewable, cacheable, and suitable for replay receipts.

## Verification

There are four proof levels.

### Structural

The Spark DSL compiles and the resource produces an `AshR2ML.Mapping.Resource`.

### Serialization

The renderer produces RDF/Turtle that parses successfully and uses valid R2RML terms.

### Relational correspondence

The mapping's logical tables, columns, and joins match a real relational schema generated/used by the Ash resources.

### Semantic execution

A real R2RML/OBDA engine queries the relational fixture through SPARQL and returns the same admitted identities and relationships observed through Ash.

Only the final level proves the complete semantic path.

## Failure model

AshR2ML refuses ambiguity instead of manufacturing false precision.

Representative failure families:

```text
invalid IRI
missing subject map
unsupported Ash datatype
incompatible RDF datatype
missing relationship predicate
ambiguous relational relationship
invalid join key
missing parent triples map
non-unique semantic identity
unsupported R2RML term type
```

`UNKNOWN`, `UNSUPPORTED`, and `REFUSED` remain distinct states.

## Non-goals

AshR2ML does not:

- implement a graph database;
- provide graph traversal storage semantics;
- replace AshPostgres;
- materialize an RDF database automatically;
- provide arbitrary OWL reasoning;
- infer missing application-profile decisions;
- execute Ash actions from RDF metadata;
- grant authorization through ontology statements.

The result is deliberately small in runtime responsibility and broad in interoperability: ordinary Ash applications can expose a standards-based semantic graph without surrendering their relational execution model.
