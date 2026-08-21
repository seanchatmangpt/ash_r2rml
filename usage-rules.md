<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
SPDX-FileCopyrightText: 2026 ash_r2ml contributors

SPDX-License-Identifier: MIT
-->

# Rules for working with AshR2ML

## What AshR2ML is

AshR2ML is a semantic mapping extension for Ash resources. It compiles Ash metadata plus explicit RDF annotations into a normalized `AshR2ML.Mapping` and standards-valid W3C R2RML.

AshR2ML does not persist records. Continue to use the Ash data layer appropriate for the application, normally `AshPostgres.DataLayer` for relational OBDA use cases.

```elixir
use Ash.Resource,
  domain: MyApp.Domain,
  data_layer: AshPostgres.DataLayer,
  extensions: [AshR2ML.Resource]
```

The governing invariant is:

```text
one Ash/relational subject
        │
        ├── Ash query surface
        ├── SQL query surface
        └── R2RML virtual RDF / SPARQL surface
```

There is no implicit RDF replica and no dual-write contract.

## Core rules

1. **Do not treat AshR2ML as an `Ash.DataLayer`.** Persistence belongs to AshPostgres or another data layer.
2. **Do not hand-maintain equivalent semantic facts in several places.** Let AshR2ML derive table, column, join, and type information from Ash when it can.
3. **Add only semantic information Ash cannot know:** class IRIs, predicate IRIs, subject construction, graph maps, explicit datatype/term-type overrides.
4. **Never silently drop a resource, attribute, relationship, identity, or unsupported type from generated R2RML.** Return a typed refusal or unsupported result.
5. **Database identity is not automatically RDF identity.** Define a subject map explicitly.
6. **Relationships are semantic edges.** An Ash relationship with an RDF predicate must compile to an R2RML reference object map when its relational join is derivable.
7. **Do not invent OWL equivalence.** Alignment metadata must preserve the exact asserted relationship.
8. **Generated ontology-first Ash is a projection.** Repair the ontology/profile/SHACL/ggen source and regenerate instead of hand-editing generated modules.
9. **ggen is a development-time manufacturer, not an ambient runtime requirement.** Applications consuming AshR2ML should not need ggen merely to execute Ash or render mappings from compiled metadata.
10. **Compile success is not semantic proof.** Integration proof requires a real relational fixture and a real R2RML/OBDA execution path.

## Resource mapping

Each mapped resource declares one or more RDF classes and exactly one effective subject construction strategy.

```elixir
r2rml do
  class "https://schema.org/Person"

  subject do
    template "https://example.org/person/{id}"
    term_type :iri
  end
end
```

Subject strategies are:

- template,
- column,
- constant,
- blank node when explicitly admitted.

A template may reference only known attributes or explicitly supported source expressions. Missing template fields are a compile-time error.

## Attribute mapping

Use `rdf` metadata inside an Ash attribute.

```elixir
attribute :name, :string do
  allow_nil? false

  rdf do
    predicate "http://xmlns.com/foaf/0.1/name"
  end
end
```

AshR2ML derives the source column and default RDF datatype from the Ash resource and data layer metadata.

Override only when necessary:

```elixir
rdf do
  predicate "https://example.org/amount"
  datatype "http://www.w3.org/2001/XMLSchema#decimal"
end
```

A datatype override must be compatible with the Ash value representation. Lossy or unverifiable coercions are refused.

## Relationship mapping

Use RDF predicate metadata on the Ash relationship:

```elixir
belongs_to :organization, MyApp.Organization do
  allow_nil? false

  rdf do
    predicate "https://schema.org/memberOf"
  end
end
```

For relational resources, AshR2ML derives:

- parent triples map,
- source/child column,
- destination/parent column,
- join condition,
- target semantic identity.

Do not duplicate foreign-key column names in the semantic DSL unless the Ash/data-layer relationship metadata cannot express them.

If a relationship cannot be deterministically mapped, return a typed error such as `AshR2ML.Error.AmbiguousRelationship` rather than emitting an incomplete mapping.

## Many-to-many and relationship resources

A many-to-many relationship may compile through its join relationship/resource when the join is fully known.

If the relationship itself carries domain facts—role, validity interval, provenance, quantity, authority, or other attributes—model it as a first-class Ash resource rather than trying to collapse those facts into a bare RDF edge.

This preserves graph topology and relational meaning simultaneously.

## Datatypes

AshR2ML maintains an explicit type-to-RDF mapping registry.

Unknown types do not fall back to `xsd:string`.

A custom type must register a lawful mapping capable of producing:

- an RDF datatype IRI or explicit term strategy,
- a lexical representation,
- validation that the conversion is information-preserving for the admitted use.

If none exists, the mapping is `UNSUPPORTED`.

## Logical tables

For AshPostgres resources, the logical table is normally derived from the `postgres` DSL.

AshR2ML also supports explicit logical-table SQL/query mappings when R2RML requires a logical view rather than a physical table, but these must be explicit and deterministic.

Do not synthesize arbitrary SQL from semantic labels.

## R2RML generation

Generate one deterministic mapping graph for a resource set:

```elixir
{:ok, ttl} = AshR2ML.R2RML.render([
  MyApp.Person,
  MyApp.Organization
])
```

The output must:

- parse as RDF/Turtle,
- use the W3C R2RML vocabulary correctly,
- contain a stable triples map identifier for each mapped resource,
- preserve configured class and predicate IRIs exactly,
- emit reference object maps for relationships,
- emit no undeclared semantic fallbacks.

Output ordering should be deterministic so regeneration can be diffed and receipted.

## Ontology-first generation

Ontology-first operation is a build/manufacturing workflow:

```text
OWL/RDFS + application profile + SHACL
                  │
                  ▼
                ggen
                  │
                  ▼
          generated Ash.Resource
                  │
                  ▼
          AshR2ML.Mapping
                  │
                  ▼
                R2RML
```

Use SHACL as the operational closure boundary. Arbitrary OWL axioms are not automatically a relational schema.

The generation pack may map, where deterministically admitted:

- `sh:targetClass` → resource class mapping,
- datatype property shape → Ash attribute,
- `sh:minCount 1` → required attribute/relationship,
- `sh:maxCount 1` object property → to-one relationship candidate,
- many-valued object property → has-many/many-to-many/association-resource candidate,
- explicit identity metadata → Ash identity + R2RML subject map.

If more than one relational representation remains lawful after applying the profile and shapes, generation must refuse instead of choosing by convention.

## Application-profile discipline

Public ontologies do not contain application storage metadata. Keep these layers separate:

```text
public ontology
      ↓
application profile / alignments
      ↓
SHACL operational shapes
      ↓
AshR2ML/ggen compiler metadata
```

Do not modify or vendor-patch public ontology terms merely to add Ash modules, PostgreSQL table names, or subject templates.

## Typed errors and refusals

AshR2ML errors must state what semantic transition failed.

Representative categories:

- invalid IRI,
- missing subject map,
- missing predicate,
- unsupported Ash type,
- incompatible RDF datatype,
- unresolved parent triples map,
- ambiguous relationship,
- invalid join condition,
- non-unique semantic identity,
- unsupported term type,
- unproven equivalence.

Compile-time DSL failures should use Spark DSL errors. Runtime mapping/rendering APIs should return typed errors rather than bare strings.

## Unknown versus unsupported

Do not collapse these states:

- **UNKNOWN** — the implementation could not determine the mapping from available metadata.
- **UNSUPPORTED** — the construct is outside the library's admitted mapping capabilities.
- **REFUSED** — the construct is understood but violates a semantic or safety invariant.

Never replace any of them with a fabricated default.

## OBDA and SPARQL

AshR2ML does not implement SPARQL execution.

Use a compatible R2RML/OBDA engine:

```text
SPARQL → OBDA rewrite → SQL → PostgreSQL
```

A library integration test is valid only when the external engine reads generated R2RML and queries a real relational fixture. Mocking the engine proves serialization, not OBDA behavior.

## Testing

The verification ladder is:

1. DSL parsing and Spark verifier tests;
2. mapping IR unit tests;
3. deterministic R2RML renderer tests;
4. Turtle/RDF parser validation;
5. AshPostgres fixture schema and CRUD tests;
6. relationship-to-reference-object-map tests;
7. real R2RML/OBDA SPARQL integration;
8. ontology-first ggen round trip where relevant.

The crown for a mapped fixture is:

```text
Ash-visible subject
      ==
SPARQL-visible virtual RDF subject
```

for the admitted semantic identities, classes, datatype properties, and object-property relationships.

## Generated code

Generated files must state their owning source and replay command. They are not editing authorities.

A change to generated code should be made through the responsible:

- ontology,
- application profile,
- SHACL shape,
- ggen query,
- ggen template,
- compiler logic.

Then regenerate and verify deterministic output.

## Security and authority

RDF metadata describes meaning. It does not grant execution authority.

Neither ontology terms, SHACL shapes, R2RML mappings, generated code, nor SPARQL queries acquire ambient permission to run application actions or mutate production state.

Ash authorization and application actuation boundaries remain authoritative.

## Contributor rule

When an implementation choice conflicts with these rules, preserve the semantic correspondence first:

```text
Ash resource/relationship
      ↕
relational representation
      ↕
R2RML mapping
```

A convenience API is not worth semantic drift.
