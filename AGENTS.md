<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# AGENTS.md — AshR2RML

Production-grade W3C R2RML, RDF semantic mapping, and DfCM type compiler layer for the Ash
Framework.

## Product Invariant

AshR2RML is **not** an `Ash.DataLayer`, graph database, triplestore, or query engine. It
compiles Ash resource metadata, semantic annotations, and ontology-first DfCM profiles into a
normalized mapping IR, standards-valid R2RML Turtle, and native `Ash.Type` representations.
`AshPostgres`/other data layers keep owning persistence.

```text
Ash.Resource + Semantic Metadata → AshR2RML.Mapping (IR) → Relational DB + R2RML (W3C Turtle)
                                                          → Ash / SQL / SPARQL (Ontop OBDA)

Ontology-first: RDF/OWL/SKOS/QUDT + Profile/SHACL → AshR2RML.SemanticTypes (DfCM Compiler)
                → generated Ash.Type/Ash.Resource → AshR2RML.Mapping (IR) → W3C R2RML Turtle
```

Both workflows converge deterministically on the same mapping IR.

## Architectural Ownership

- **Ash** — resource, action, identity, calculation, aggregate, domain authorization.
- **AshPostgres / relational data layers** — persistence, tables, indexes, FKs.
- **AshR2RML** — semantic mapping metadata, introspection, IR, R2RML rendering, DfCM type compilation.
- **Ontop** — virtual RDF graph projection, SPARQL-to-SQL rewriting.
- **Ash.Reactor** — transactional sagas, async DAG execution, strict LIFO compensation/undo.
- **IEEE OCEL 2.0 Telemetry** — event multigraph streaming, sequence integrity, trace reconstruction.

Do not blur these boundaries.

## Core Semantic Correspondences

| Construct | Ash | Relational DB | W3C R2RML |
|---|---|---|---|
| RDF/OWL Class | `Ash.Resource` (`class_iri`) | Table/View | `rr:class` |
| Datatype Property | `Attribute` | Column | `rr:predicate`/`rr:datatype` |
| Object Property | `Relationship` | FK/Join Table | `rr:RefObjectMap` (`rr:parentTriplesMap`/`rr:joinCondition`) |
| Semantic Identity | Subject Mapping | Unique/Composite Key | Subject Map (`rr:template`/`rr:termType`) |
| Datatype | `Ash.Type`/`AshR2RML.Type` | Storage Type | `rr:datatype` |
| Scalar Multiplicity | `allow_nil? false` | `NOT NULL` | Object Map + SHACL `sh:minCount 1` |
| To-One Edge | `belongs_to`/`has_one` | FK | `rr:RefObjectMap` |
| To-Many Edge | `has_many`/`many_to_many` | FK/assoc table | Repeated `rr:RefObjectMap` |

A mapping is valid only if the same semantic relationship/identity survives every projection.

## Normalized Mapping IR

All compilation surfaces converge on: `AshR2RML.Mapping.{Resource, SubjectMap,
PredicateObjectMap, ReferenceObjectMap, JoinCondition, Datatype, GraphMap}`,
`AshR2RML.SemanticType{, .Plan}`. **Normalize to IR first, verify second, render third** —
never render R2RML Turtle directly from ad-hoc resource inspection.

## Resource DSL

```elixir
defmodule MyApp.Person do
  use Ash.Resource, extensions: [AshR2RML]

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
      rdf do: predicate("http://xmlns.com/foaf/0.1/name")
    end
  end

  relationships do
    belongs_to :organization, MyApp.Organization do
      rdf do: predicate("https://schema.org/memberOf")
    end
  end
end
```

## Semantic Identity & Datatype Laws

- Database identity and RDF identity are distinct. Subject mappings use IRI templates,
  attribute-column mappings, constant IRIs, or explicitly admitted blank nodes.
- Every template `{field}` must resolve to a real mapped attribute; `rr:RefObjectMap` joins
  must target stable unique identities. Never derive an IRI from a module name or internal row
  ID unless explicitly mapped.
- Custom types implement `AshR2RML.Type` (`semantic_kind/0`, `datatype_iri/0`, `to_rdf/1`,
  `from_rdf/1`). Never fall back to `unknown Ash type → string`; refuse
  (`REFUSED_UNMAPPED_DATATYPE`) instead.

## Typed Refusals

Prefer typed failures to silent degradation: `REFUSED_INVALID_CLASS_IRI`,
`REFUSED_MISSING_SUBJECT_MAP`, `REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY`,
`REFUSED_UNMAPPED_DATATYPE`, `REFUSED_AMBIGUOUS_RELATIONSHIP`, `REFUSED_INVALID_JOIN_CONDITION`,
`REFUSED_RELATIONSHIP_WITHOUT_PREDICATE`, `REFUSED_R2RML_JOIN_WITHOUT_IDENTITY`,
`REFUSED_UNPROVEN_EQUIVALENCE`, `REFUSED_SEMANTIC_TYPE_INVALID`,
`REFUSED_SEMANTIC_TYPE_ASH_MISMATCH`, `REFUSED_SEMANTIC_TYPE_REQUIRES_RESOURCE_PROJECTION`,
`REFUSED_SEMANTIC_ROUND_TRIP`, `REFUSED_UNSUPPORTED_SPARQL_FEATURE`. Compile-time DSL
violations fail at compile time; runtime mapping APIs return `{:error, %AshR2RML.Refusal{}}`.

## Ash.Reactor Integration

Native Zach Daniel-style sagas: modular steps (`AshR2RML.Reactor.Steps.*`) with 3-arity
`run/3`/`compensate/4`/`undo/3`; async DAG dependencies resolve with topological partial-order
preservation; `AshR2RML.Reactor.Middleware.TelemetryLogger` emits IEEE OCEL 2.0 event streams;
compensation on failure runs in strict reverse LIFO order.

## Query Backend Security

Both query backends now honor Ash field policies, structurally, without an operator having to
remember to. `AshR2RML.OBDA.InMemory` is Ash-mediated (`Ash.read!/2`), so denied fields
(`%Ash.ForbiddenField{}`) are omitted for real, and every IRI built from row data is
percent-encoded (fail-closed against Turtle/IRIREF injection). Ontop connects to
`AshPostgres.DataLayer` directly over JDBC with no Ash actor context, so
`AshR2RML.Security.sanitize_mapping/2` (wired into `AshR2RML.Compiler.compile_resources/1`)
strips any R2RML-mapped attribute that carries an explicit `field_policy` from the mapping
*before* it can be rendered or handed to Ontop — the exclusion is recorded in
`mapping.metadata[:field_policy_excluded_attributes]` for auditability.

## Verification & Release Ladder

1. `mix format --check-formatted`
2. `mix compile --warnings-as-errors`
3. `mix test test/unit/`
4. `mix test test/adversarial/ test/negative/`
5. `mix test test/fortune5/`
6. `mix test test/adversarial/ontop_postgres_test.exs` (live Ontop 5.5 OBDA over Postgres)
7. `mix test test/adversarial/reactor_saga_test.exs`
8. `mix hex.build`
9. GitHub Actions: `v*` tags trigger CalVer publication to Hex.pm (`.github/workflows/release.yaml`)

## Standing Vocabulary

`UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`, `BUILD_BROKEN`, `UNSUPPORTED`, `REFUSED_<TYPE>`.
