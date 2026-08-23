<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# AGENTS.md — AshR2RML

This repository is the production-grade W3C R2RML, RDF semantic mapping, and DfCM type compiler layer for the Ash Framework.

## Product Invariant

AshR2RML is **not** an `Ash.DataLayer`, graph database, triplestore, or proprietary query engine.

AshR2RML compiles Ash resource metadata, explicit semantic annotations, and ontology-first DfCM semantic profiles into a normalized mapping IR, standards-valid W3C R2RML mappings, and native `Ash.Type` representations. Existing Ash data layers (such as `AshPostgres`) continue to own persistence.

```text
Ash.Resource + Semantic Metadata
             │
             ▼
      AshR2RML.Mapping (IR)
         ╱         ╲
        ▼           ▼
 Relational DB    R2RML (W3C Turtle)
        │           │
        └─────┬─────┘
              ▼
       ONE SUBJECT
       Ash / SQL / SPARQL (Ontop OBDA)
```

For ontology-first / DfCM manufacturing:

```text
W3C RDF / OWL / SKOS / QUDT Ontologies
                │
                ▼
  Application Profile + SHACL Shapes
                │
                ▼
 AshR2RML.SemanticTypes (DfCM Compiler)
                │
                ▼
 Generated Ash.Type & Ash.Resource
                │
                ▼
      AshR2RML.Mapping (IR)
                │
                ▼
          W3C R2RML Turtle
```

Both Ash-first and ontology-first workflows converge deterministically on the same mapping IR.

---

## Architectural Ownership

Keep domain and runtime boundaries explicit:

- **Ash Framework** owns resource, action, identity, calculation, aggregate, and domain authorization semantics.
- **AshPostgres / Relational Data Layers** own relational persistence, tables, indexes, constraints, and foreign keys.
- **AshR2RML** owns semantic mapping metadata, AST introspection, compile-time validation, normalized mapping IR, standards-valid R2RML rendering, and DfCM semantic type compilation.
- **Ontop / OBDA Engine** owns virtual RDF graph projection and SPARQL-to-SQL query rewriting.
- **Ash.Reactor** owns transactional sagas, asynchronous DAG execution, and strict LIFO compensation/undo rollbacks.
- **IEEE OCEL 2.0 Telemetry** owns real-time event multigraph streaming, sequence integrity, and trace reconstruction.

Do not blur or move responsibilities across these boundaries.

---

## Core Semantic Correspondences

AshR2RML preserves exact semantic correspondences across all representations:

| Semantic Construct | Ash Framework Projection | Relational Database Projection | W3C R2RML Projection |
|---|---|---|---|
| **RDF / OWL Class** | `Ash.Resource` (`class_iri`) | Table or SQL View | `rr:class` |
| **Datatype Property** | `Ash.Resource.Attribute` | Column / Expression | Predicate-Object Map (`rr:predicate`, `rr:datatype`) |
| **Object Property** | `Ash.Resource.Relationship` | Foreign Key / Join Table | Reference Object Map (`rr:parentTriplesMap`, `rr:joinCondition`) |
| **Semantic Identity** | Subject Mapping / Identity | Unique Key / Composite PK | Subject Map (`rr:template`, `rr:termType`) |
| **Datatype** | `Ash.Type` / `AshR2RML.Type` | Storage / DB Type | `rr:datatype` (e.g. `xsd:string`, `xsd:dateTime`) |
| **Scalar Multiplicity** | `allow_nil? false` | `NOT NULL` Constraint | Object Map + SHACL `sh:minCount 1` |
| **To-One Edge** | `belongs_to` / `has_one` | Foreign Key | `rr:RefObjectMap` with `rr:child`/`rr:parent` |
| **To-Many Edge** | `has_many` / `many_to_many` | FK / Association Table | Repeated Reference Object Maps |

A mapping is valid only if the exact same admitted semantic relationship and identity survive intact across all projections.

---

## Normalized Mapping IR

All public compilation surfaces must converge on deterministic, inspectable IR structures:

```text
AshR2RML.Mapping.Resource
AshR2RML.Mapping.SubjectMap
AshR2RML.Mapping.PredicateObjectMap
AshR2RML.Mapping.ReferenceObjectMap
AshR2RML.Mapping.JoinCondition
AshR2RML.Mapping.Datatype
AshR2RML.Mapping.GraphMap
AshR2RML.SemanticType
AshR2RML.SemanticType.Plan
```

Never generate R2RML Turtle directly from ad-hoc resource inspection in scattered code paths. **Normalize to IR first, verify second, render third.**

---

## Resource DSL & Declarations

The public DSL exposes only semantic information that Ash cannot infer:

```elixir
defmodule MyApp.Person do
  use Ash.Resource,
    extensions: [AshR2RML]

  r2rml do
    class "https://schema.org/Person"

    subject do
      template "https://example.org/people/{id}"
      term_type :iri
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      rdf do
        predicate "http://xmlns.com/foaf/0.1/name"
      end
    end
  end

  relationships do
    belongs_to :organization, MyApp.Organization do
      rdf do
        predicate "https://schema.org/memberOf"
      end
    end
  end
end
```

---

## Semantic Identity Law

Database identity and RDF identity are distinct:

- Subject mappings may use **IRI templates**, **attribute column mappings**, **constant IRIs**, or explicitly admitted **blank nodes**.
- Every template parameter `{field}` must resolve to a real mapped attribute on the resource.
- Joins used by `rr:RefObjectMap` must target stable unique identities.
- Never silently construct an RDF IRI from an Elixir module name or internal database row ID unless explicitly mapped.

---

## Datatype Law

Datatype conversion must be explicit, lossless, and semantic-aware:

- Custom types implement the `AshR2RML.Type` behaviour (`semantic_kind/0`, `datatype_iri/0`, `to_rdf/1`, `from_rdf/1`).
- Never implement a fallback of `unknown Ash type → string`.
- If no lawful RDF datatype or representation is known, return a typed refusal (`REFUSED_UNMAPPED_DATATYPE`).

---

## Typed Refusals

Prefer typed semantic failures to silent degradation or unhandled crashes:

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
REFUSED_SEMANTIC_TYPE_INVALID
REFUSED_SEMANTIC_TYPE_ASH_MISMATCH
REFUSED_SEMANTIC_TYPE_REQUIRES_RESOURCE_PROJECTION
REFUSED_SEMANTIC_ROUND_TRIP
```

Compile-time DSL violations must fail at compile time. Runtime mapping APIs return `{:error, %AshR2RML.Refusal{}}`.

---

## Ash.Reactor Integration Law

AshR2RML provides native Zach Daniel-style `Ash.Reactor` sagas:

- Steps are modular (`AshR2RML.Reactor.Steps.*`) with 3-arity `run/3`, `compensate/4`, and `undo/3` hooks.
- Asynchronous DAG dependencies resolve concurrently with topological partial-order preservation.
- Intercepts lifecycle execution via custom middleware (`AshR2RML.Reactor.Middleware.TelemetryLogger`) and emits IEEE OCEL 2.0 event streams.
- On failure, compensation rollbacks execute in strict reverse LIFO order.

---

## Verification & Release Ladder

Verification proceeds through the strict ascending ladder:

1. **Syntax & Formatting:** `mix format --check-formatted`.
2. **Type Safety & Compilation:** `mix compile --warnings-as-errors`.
3. **Pure Unit & Mapping IR Tests:** `mix test test/unit/`.
4. **Adversarial Closure & Refusal Suites:** `mix test test/adversarial/ test/negative/`.
5. **Fortune 5 Enterprise Systems & ODRL Policies:** `mix test test/fortune5/`.
6. **Ontop 5.5 Virtual OBDA Live SPARQL:** `mix test test/adversarial/ontop_postgres_test.exs`.
7. **Reactor Saga Sagas & Rollbacks:** `mix test test/adversarial/reactor_saga_test.exs`.
8. **Package Build:** `mix hex.build`.
9. **GitHub Actions CI & CalVer Release:** Release tags matching `v*` trigger automated publication to Hex.pm via `.github/workflows/release.yaml`.

---

## Standing Vocabulary

- `UNKNOWN`
- `PARTIAL_ALIVE`
- `ALIVE`
- `BLOCKED`
- `BUILD_BROKEN`
- `UNSUPPORTED`
- `REFUSED_<TYPE>`
