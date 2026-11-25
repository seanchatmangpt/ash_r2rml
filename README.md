<!--
SPDX-FileCopyrightText: 2025 Matthew Graham Beanland and contributors
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# AshR2RML

**Semantic mappings for Ash. Keep PostgreSQL relational; expose the same admitted subject as RDF.**

AshR2RML is an Ash extension that compiles Ash resources and relationships into standards-valid W3C R2RML mappings. It lets an Ash application persist through its normal data layer—typically AshPostgres—while exposing the same state as RDF through standards-valid R2RML Turtle and the Ash-mediated `AshR2RML.OBDA.InMemory` runtime (the only OBDA backend shipped; no external engine is verified).

AshR2RML is **not** a graph database, **not** an `Ash.DataLayer`, and **not** a database-side SPARQL-to-SQL rewriting engine.
SPARQL is evaluated in-process (`AshR2RML.SPARQL.Local`) over rows read through Ash.

### Scope (v26.11.24)

**Shipped**

- Sole runtime OBDA backend: `AshR2RML.OBDA.InMemory` (Ash-mediated `Ash.read/2` under the
  caller's actor/tenant). `AshR2RML.OBDA.query/3` bounds every evaluation with `max_rows`,
  `max_triples`, `max_heap_words` (worker-process isolation), and `timeout_ms`. Attributes marked
  `sensitive?: true` are refused unless `allow_sensitive?: true` (`allow_sensitive: true` is also
  accepted by `OBDA.query/3`; `OBDA.InMemory` takes `allow_sensitive`).
- `Ash.Query` pushdown (constant-subject lookups; simple FILTER, ORDER BY, LIMIT/OFFSET on the
  root resource) and resource preflight pruning.
- A read-only HTTP SPARQL protocol client (`AshR2RML.SPARQL.Protocol`).
- Runtime deps: `ash`, `spark`, `rdf`, `sparql`, `sparql_client`, `jason`, `telemetry`
  (`igniter` optional). Zero Java, zero JDBC, no data-layer dependency; all reads go through Ash
  actions. `lib/mix` tasks are not shipped in the Hex package.
- No external-engine OBDA is verified; the earlier Ontop/JDBC adapter was removed.
- R2RML Turtle from `AshR2RML.R2RML.render/1` is the frozen wire contract for a future
  PurRDF/graphlaw backend.

**Explicitly NOT built**

- Federated query mesh (no multi-endpoint federation or `SERVICE` routing; a single bounded
  remote SPARQL endpoint client ships as `AshR2RML.SPARQL.Protocol`)
- Reverse actuation (RDF writes back into Ash)
- AOT `.rq` compile
- Live streaming

**Documented divergence.** Ash field policies strip fields per actor on the Ash-mediated
path. R2RML Turtle rendered for a SQL/Postgres-backed engine reads columns directly and
cannot apply those field policies, so the two surfaces can differ for the same subject.

**Test tiers**

- ETS (default): `mix test`
- SQLite: `mix test --include sqlite`
- Postgres: set `ASH_R2RML_POSTGRES_URL`, then `mix test --include postgres`

Its job is narrower and more useful:

```text
Ash.Resource + semantic mapping
             │
             ▼
      AshR2RML.Mapping
         ╱         ╲
        ▼           ▼
  AshPostgres     R2RML
        │           │
        ▼           ▼
   PostgreSQL   virtual RDF graph
        │           │
        └─────┬─────┘
              ▼
       ONE SUBJECT
       SQL / Ash / SPARQL
```

The same facts are not synchronized between two databases. PostgreSQL remains the operational store; R2RML defines a semantic projection over it.

## Why AshR2RML

A conventional semantic integration often starts too late:

```text
application schema → database tables → retrofit RDF mapping
```

AshR2RML starts from the Ash resource instead: the resource declares its semantics once, and the R2RML mapping is compiled from it.

```text
Ash.Resource + r2rml/rdf DSL
            │
            ▼
     AshR2RML.Mapping (IR)
        ╱          ╲
       ▼            ▼
 AshPostgres      R2RML → OBDA engine
```

That gives an application three lawful query surfaces over one admitted subject:

- Ash queries and actions for application behavior.
- SQL for relational analytics and operations.
- SPARQL over the virtual RDF graph for semantic interoperability.

## Installation

Add AshR2RML beside the Ash data layer you already use:

```elixir
def deps do
  [
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},  # your own data layer; not a dependency of ash_r2rml
    {:ash_r2rml, "~> 26.11"}
  ]
end
```

AshR2RML has no data-layer dependency and does not replace AshPostgres. A resource continues to use its normal data layer:

```elixir
defmodule MyApp.Person do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]
end
```

## Ash-first quick start

Define the relational resource normally, then add only the semantic information Ash cannot infer.

```elixir
defmodule MyApp.Person do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]

  postgres do
    table "people"
    repo MyApp.Repo
  end

  r2rml do
    class "http://xmlns.com/foaf/0.1/Person"

    subject template: "urn:uuid:{id}", term_type: :iri

    property :name, "http://xmlns.com/foaf/0.1/name"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end
  end
end
```

AshR2RML introspects the Ash resource, its data layer metadata, attributes, identities, and relationships and compiles them into a normalized mapping.

```elixir
mapping = AshR2RML.Resource.Info.mapping(MyApp.Person)
```

Generate R2RML:

```elixir
{:ok, turtle} = AshR2RML.R2RML.render([MyApp.Person])
File.write!("priv/r2rml/application.ttl", turtle)
```

The resulting triples map is equivalent in shape to:

```turtle
<#Person>
    a rr:TriplesMap ;
    rr:logicalTable [ rr:tableName "people" ] ;
    rr:subjectMap [
        rr:template "urn:uuid:{id}" ;
        rr:class foaf:Person ;
        rr:termType rr:IRI
    ] ;
    rr:predicateObjectMap [
        rr:predicate foaf:name ;
        rr:objectMap [
            rr:column "name" ;
            rr:datatype xsd:string
        ]
    ] .
```

## Relationships are semantic edges

Ash relationships are first-class inputs to the mapping compiler.

```elixir
r2rml do
  reference :organization, "https://schema.org/memberOf"
end

relationships do
  belongs_to :organization, MyApp.Organization do
    allow_nil? false
  end
end
```

For a relational data layer, AshR2RML derives the join from the relationship metadata and emits an R2RML reference object map:

```turtle
rr:predicateObjectMap [
    rr:predicate schema:memberOf ;
    rr:objectMap [
        rr:parentTriplesMap <#Organization> ;
        rr:joinCondition [
            rr:child "organization_id" ;
            rr:parent "id"
        ]
    ]
] .
```

One admitted relationship therefore has three corresponding projections:

```text
Ash relationship
      │
      ├── PostgreSQL FK / join structure
      └── R2RML RefObjectMap / RDF object property
```

AshR2RML refuses mappings that cannot be derived without inventing semantics.

## Semantic identity

Database identity and RDF identity are separate concerns.

AshR2RML supports subject maps based on:

- IRI templates,
- a column,
- a constant IRI,
- blank nodes where explicitly configured.

Example:

```elixir
r2rml do
  class "https://schema.org/Organization"

  subject template: "urn:uuid:{tenant_id}-{id}", term_type: :iri
end
```

Every template field must resolve to an admitted Ash attribute. Subject construction is validated at compile time; invalid or ambiguous identity mappings are refused rather than guessed.

## Datatypes

AshR2RML maps Ash types to RDF datatypes through an explicit datatype registry.

Typical built-ins include:

| Ash type | RDF datatype |
|---|---|
| `:string` | `xsd:string` |
| `:integer` | `xsd:integer` |
| `:boolean` | `xsd:boolean` |
| `:decimal` | `xsd:decimal` |
| `:date` | `xsd:date` |
| UTC datetime types | `xsd:dateTime` |
| `:uuid` | `xsd:string` unless overridden |
| `:duration` (`Ash.Type.Duration`, Ash >= 3.23) | `xsd:duration` |

A type with no lawful mapping is `UNSUPPORTED`; it is never silently coerced to a string.

Custom Ash types can implement the AshR2RML datatype contract to define their RDF lexical form and datatype IRI.

## The mapping intermediate representation

Every public entry path compiles to the same IR:

```text
AshR2RML.Mapping.Resource
AshR2RML.Mapping.SubjectMap
AshR2RML.Mapping.PredicateObjectMap
AshR2RML.Mapping.ReferenceObjectMap
AshR2RML.Mapping.JoinCondition
AshR2RML.Mapping.Datatype
AshR2RML.Mapping.GraphMap
```

This representation is deliberately close to R2RML terminology. It is inspectable, deterministic, and independent of any one application ontology.

```elixir
%AshR2RML.Mapping.Resource{
  ash_resource: MyApp.Person,
  logical_table: %AshR2RML.Mapping.LogicalTable{table_name: "people"},
  subject_map: %AshR2RML.Mapping.SubjectMap{...},
  class_iris: ["http://xmlns.com/foaf/0.1/Person"],
  predicate_object_maps: [...],
  reference_object_maps: [...],
  graph_maps: [],
  identities: [],
  metadata: %{}
}
```

## Unreleased capabilities

Named graphs (`graph "iri"`), money composites (`AshR2RML.Money`), temporal intervals
(`temporal start_attribute:, end_attribute:`), the AshCloak enclave guard, and opt-in strict
domain mode (`r2rml_domain do strict? true end`). Downstream handoff contract: deterministic
R2RML, canonical N-Quads (`AshR2RML.NQuads`), invertible `AshR2RML.Subject` codec, and the
`AshR2RML.OBDA.Result` digest. Details and status: `CHANGELOG.md` under "Unreleased".

## Typed refusals

AshR2RML fails closed at semantic boundaries. Representative failures include:

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

The exact Elixir error is a typed AshR2RML/Spark error. No mapping path silently drops a resource, attribute, relationship, or identity.

## Virtual RDF, not RDF synchronization

AshR2RML generates mappings; `AshR2RML.OBDA.InMemory` executes SPARQL by reading through Ash
(policies, field policies, tenants and the resource's own data layer), then evaluating in-process.

```text
SPARQL
   │
   ▼
OBDA.InMemory
   │ Ash.read (policy, tenant, limits)
   ▼
Ash data layer (ETS / SQLite / PostgreSQL)
```

There is no RDF replication requirement and no dual-write protocol. The RDF graph is virtual unless the application deliberately materializes it elsewhere.

This eliminates an entire class of synchronization drift:

```text
Postgres row/FK state == source of truth
RDF triples            == semantic projection of that state
```

## Architecture invariant

AshR2RML follows this correspondence:

| Semantic construct | Ash | Relational projection | R2RML |
|---|---|---|---|
| RDF/OWL class | Resource | table/view | `rr:class` |
| datatype property | attribute | column/expression | predicate-object map |
| object property | relationship | FK/join | reference object map |
| semantic identity | subject DSL / Ash identity | unique key(s) | subject map |
| datatype | Ash type | storage type | `rr:datatype` |
| required property | `allow_nil? false` | NOT NULL where applicable | shape constraint |
| one-to-one / many-to-one | relationship | FK | reference object map |
| many-to-many | relationship/join resource | join table | chained reference maps |

R2RML should name and expose relationships the relational model already preserves. It should not repair a semantically impoverished schema.

## Verification model

AshR2RML treats compile success as a checkpoint, not the crown.

The verified path is in-process:

```text
Ash resources
    ↓
AshR2RML mapping IR
    ↓
OBDA.InMemory (Ash.read/2, actor/tenant)
    ↓
SPARQL.Local
```

The semantic identity and required relationships returned through SPARQL must match the subject visible through Ash. Rendered R2RML Turtle for an external R2RML engine is not exercised against any such engine.

## Status

This repository is **PARTIAL_ALIVE**, not a finished product. As of v26.11.24 it is stripped to
the core: the `r2rml`/`rdf` DSL, the mapping IR, R2RML rendering, a typed refusal vocabulary, and
one runtime OBDA backend (`AshR2RML.OBDA.InMemory`: Ash-mediated `Ash.read/2` with `actor:`/`tenant:`
over any Ash data layer) plus a read-only HTTP SPARQL protocol client. Zero Java, zero JDBC.

Current surface:

- `AshR2RML.Compiler.compile/2` accepts a resource, a list, or an `Ash.Domain` (expanded to the
  domain's resources carrying the extension).
- `mix ash_r2rml.render MyApp.Person MyApp.Domain` renders R2RML Turtle for resources or domains. This task lives in the repository checkout only: the Hex package ships no `lib/mix` tasks, so consumers call `AshR2RML.R2RML.render/1` directly.
- `AshR2RML.Subject.to_iri/2` and `from_iri/2` convert between records/keys and subject IRIs;
  `Subject.iri_only?/1` reports whether a mapping yields only IRI subjects (no blank nodes).
- `OBDA.InMemory` reads run with `authorize?: true` by default. Weakening is explicit and refused
  otherwise: `authorize?: false` needs `allow_unauthorized: true`; `require_authorizer: true`
  refuses resources without `Ash.Policy.Authorizer`; `require_tenant: true` refuses multitenant
  reads without `:tenant`.
- SELECT results without `ORDER BY` are returned in canonical row order, so output is deterministic.
- `SPARQL.Protocol.query/3` refuses private-network endpoints unless `allow_private_network: true`.

Removed in v26.11.24 and recoverable from git history (commit `5defc87`): ontology-first
ingestion and semantic types, ggen packs, GraphQL projection, Reactor sagas, OCEL telemetry,
knowledge hooks, VKG, federation, DfCM and production admission.

Named gaps:

- `Ash.Type.Range` has no R2RML datatype mapping yet (`UNSUPPORTED_ASH_TYPE`).
- OBDA verification against an external SPARQL-to-SQL engine is UNVERIFIED by design: the Ontop/JDBC
  adapter and its live crowns were removed in v26.11.24 (recoverable from commit `26f5f49`). Evidence
  is the in-process `InMemory` and `SPARQL.Local` suites, including field-policy denial
  (`test/obda_in_memory_field_policy_denial_test.exs`) and the zero-JDBC guard (`test/zero_jdbc_guard_test.exs`).

Never treat this README, `AGENTS.md`, or `CHANGELOG.md` as proof a capability is wired end to
end — the real evidence is the cited test file and its actual passing run.

## What AshR2RML does not do

AshR2RML deliberately does not:

- replace AshPostgres, AshSql, Ecto, or another Ash data layer;
- store RDF triples itself;
- rewrite SPARQL to SQL (only the bounded `Ash.Query` pushdown listed above ships);
- infer arbitrary OWL semantics;
- invent missing relationship or identity information;
- make generated ontology facts executable with ambient authority.

## Development

The repository's `AGENTS.md` is the authoritative contributor contract.

## License

MIT. See `LICENSES/MIT.md`.
