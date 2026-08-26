<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# AshR2RML Agent Operating Contract

This contract governs the repository unless a deeper `AGENTS.md` narrows a subtree. Live tree evidence outranks stale prose. Nested doctrine may tighten constraints but may not silently weaken evidence, semantic correspondence, authority, replay, or publication law.

## Product invariant

AshR2RML is the W3C R2RML/RDF semantic-mapping and DfCM type-compiler layer for Ash Framework. It is **not** an `Ash.DataLayer`, graph database, triplestore, proprietary query engine, or replacement persistence layer.

Ash resource metadata, explicit semantic annotations, and ontology-first profiles must normalize into one deterministic mapping IR before verification/rendering. Ash-first and ontology-first workflows must converge on the same admitted semantic subject.

Ownership remains explicit: Ash owns resource/action/domain semantics; relational and other Ash data layers own persistence; AshR2RML owns semantic metadata, introspection, compile-time validation, normalized IR, R2RML rendering, and semantic type compilation; Ontop/OBDA owns virtual graph projection and SPARQL→SQL rewriting; `AshR2RML.OBDA.InMemory` owns in-process RDF materialization/SPARQL execution over real Ash reads from any supported Ash data layer; Ash.Reactor owns saga/DAG execution and rollback; OCEL telemetry owns event-stream/trace reconstruction. Do not blur these boundaries.

## Preserve → Fence → Calculus

Resolve repo/ref/base to an exact commit and read applicable root+nested doctrine, README/docs, `mix.exs`, lockfile, CI, release workflow, generators, and test layout. Preserve public DSL/API, normalized IR, semantic identity, datatype law, correspondence, typed refusals, generated/manual ownership, and reversible alternatives. Apply Chesterton's fence before removing an existing boundary. One failed edge is topology, not graph failure.

`A = μ(O*)`; `R = receipt(A)`. Separate `SELECT`, `CONSTRUCT`, `DO`. Model/planner/generator/proof/hook output has no ambient execution authority. Hooks manufacture intents, never actuate. Consequential execution uses the repository's admitted Ash/Reactor/runtime boundary and must be receipted.

## Evidence / standing

Use `UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED | BUILD_BROKEN | UNSUPPORTED` plus typed `REFUSED_*`. `ALIVE` requires observed execution against the exact admitted subject. Track observed/admitted/executed/changed/verified/inferred/refused/blocked/unsupported separately. Inspection is not execution; compile metadata is not an executed mapping; emitted Turtle is not proven semantic equivalence; a workflow is not a successful run.

## Semantic correspondence law

Preserve the same admitted class, attribute/property, relationship/join, subject identity, datatype, cardinality, and graph semantics across Ash, relational, IR, R2RML, SHACL/profile, and OBDA projections. Normalize to IR first, verify second, render third. Never generate R2RML directly from scattered ad-hoc inspection paths.

Database identity and RDF identity are distinct. Subject templates/columns/constants/blank nodes must be explicit; every template field resolves to a mapped attribute; reference joins target stable unique identities. Never derive semantic IRIs silently from module names or internal row IDs.

Datatype conversion must be explicit and lossless. Unknown Ash types must not silently degrade to strings. Preserve typed semantic refusals for invalid IRIs, missing subject maps, non-unique identity, unmapped datatypes, ambiguous relationships, invalid joins, missing predicates/identity, unproven equivalence, invalid semantic types, type/Ash mismatch, projection requirements, unsupported SPARQL features, and failed semantic round trips. Compile-time DSL violations fail at compile time; runtime APIs return the repository's typed refusal structure (`{:error, %AshR2RML.Refusal{}}`).

The concrete correspondence table and code-level reference for the above live in [Concrete Reference](#concrete-reference) below — this section states the law; that section names the exact modules/functions that implement it.

## Reactor / generated surfaces

Preserve native Ash.Reactor step contracts, dependency order/concurrency semantics, middleware telemetry, and strict reverse rollback where the live implementation requires them. Generated artifacts are projections: edit their owning ontology/profile/IR/schema/template/generator rather than hand-editing outputs.

## Query backend security

Semantic publication has its own authority boundary. **Readable by an Ash process is not equivalent to admitted for RDF publication.** The governing invariant is `RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`.

`AshR2RML.OBDA.InMemory` is Ash-mediated (`Ash.read!/2`), so denied fields (`%Ash.ForbiddenField{}`) are omitted and row-derived IRIs are validated or percent-encoded. That is necessary but not sufficient: an Ash extension can replace an admitted attribute with a derived field that an ordinary read loads automatically. `ash_cloak` is the observed falsifier — it replaces a cloaked attribute with a sensitive decrypting calculation under the same public name, and `decrypt_by_default` causes ordinary reads to carry plaintext. Therefore `AshR2RML.Security.sanitize_in_memory_mapping/2` is an obligatory pre-materialization admission transform. Any mapped scalar name that no longer resolves through `Ash.Resource.Info.attribute/2` is removed before graph construction and recorded in `mapping.metadata[:in_memory_non_attribute_excluded_attributes]`. Calculations, aggregates, or extension-manufactured fields have no ambient RDF-publication authority merely because their values are loaded into the record struct.

Ontop connects to `AshPostgres.DataLayer` directly over JDBC with no Ash actor context, so `AshR2RML.Security.sanitize_mapping/2` (wired into `AshR2RML.Compiler.compile_resources/1`) strips any R2RML-mapped attribute that carries an explicit `field_policy` from the mapping *before* it can be rendered or handed to Ontop — the exclusion is recorded in `mapping.metadata[:field_policy_excluded_attributes]` for auditability. This is a structural exclusion, not a refusal gate: it never blocks compilation, and it deliberately does not attempt to distinguish an unconditional `authorize_if always()` policy from a genuinely conditional one.

## Work / verification

Follow `parse → orient → resolve → materialize → read doctrine → inspect → admit/refuse → diagnose/repair → construct → actuate → receipt → replay → standing`. Prefer the existing lawful path and smallest coherent diff. No fabricated evidence, weakened tests, acceptance mocks for real DB/OBDA/Reactor claims, unrelated refactors, or unresolved production placeholders.

Acceptance precedence: exact user behavior/command → live documented repository command → narrowest equivalent. Discover the current ladder from `mix.exs`, tests, CI, and release workflow at the admitted SHA rather than freezing it here. Preserve the intended progression across formatting/compilation, pure IR tests, adversarial/refusal tests, enterprise/policy cases, live OBDA integration (both Ontop+Postgres and in-process `AshR2RML.OBDA.InMemory`), Reactor rollback, package build, and release gates when those surfaces exist. CI supplements local execution; it is not truth.

As of this writing that ladder is: `mix format --check-formatted` → `mix compile --warnings-as-errors` → `mix test test/unit/` → `mix test test/adversarial/ test/negative/` → `mix test test/fortune5/` → `mix test test/adversarial/ontop_postgres_test.exs` (live Ontop 5.5 OBDA over Postgres) → `mix test test/adversarial/reactor_saga_test.exs` → `mix hex.build` → GitHub Actions `v*` tags trigger CalVer publication to Hex.pm (`.github/workflows/release.yaml`). Re-derive this from the repository rather than trusting it once it goes stale.

## GitHub / receipt

Never silently move the admitted base. Unless explicitly instructed otherwise: purpose branch, intentional commit, non-force push, draft PR, no merge. Final receipt identifies repo/base/tree, O/O*, transports/failures, changed/generated surfaces, commands/exits, verification ladder, receipt/replay, branch/SHA/PR, semantic standing, and falsifiers.

---

## Concrete Reference

The sections above are the durable process/evidence contract. This section is the current
code-level reference implementing it — re-verify against the live tree before trusting it,
per "live tree evidence outranks stale prose" above.

### Architecture at a glance

```text
Ash.Resource + Semantic Metadata → AshR2RML.Mapping (IR) → Relational DB + R2RML (W3C Turtle)
                                                          → Ontop OBDA (Postgres) | AshR2RML.OBDA.InMemory (Ash read)

Ontology-first: RDF/OWL/SKOS/QUDT + Profile/SHACL → AshR2RML.SemanticTypes (DfCM Compiler)
                → generated Ash.Type/Ash.Resource → AshR2RML.Mapping (IR) → W3C R2RML Turtle
```

All compilation surfaces converge on: `AshR2RML.Mapping.{Resource, SubjectMap,
PredicateObjectMap, ReferenceObjectMap, JoinCondition, Datatype, GraphMap}`,
`AshR2RML.SemanticType{, .Plan}`.

### Core semantic correspondences

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

### Resource DSL

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

### Two query-execution backends

- **`AshR2RML.OBDA.InMemory`** materializes resources from any real Ash data layer reachable by
  `Ash.read!/2` into a real `RDF.Graph`, after `sanitize_in_memory_mapping/2` closes derived-field
  disclosure, then runs full SPARQL (`SELECT`/`ASK`/`CONSTRUCT`/`DESCRIBE`) through
  `AshR2RML.SPARQL.Local`/`SPARQL.ex`. Supports `materialize_many/2`/`query_many/3` for
  cross-resource joins via `reference_object_maps`, including composite-key (multi-column)
  `rr:joinCondition`s; a `:join_table` many-to-many shape is an explicit typed refusal, not a
  silent omission.
- **`AshR2RML.OBDA.Ontop`** executes the rendered R2RML mapping against `AshPostgres.DataLayer`
  via the Ontop CLI over JDBC. See "Query backend security" above for the security asymmetry
  between these two surfaces.
- **`AshR2RML.Compiler.compile/2`** accepts `storage_backend: :postgres | :ets` (default
  `:postgres`); `:ets` skips SQL DDL rendering (`Ash.DataLayer.Ets` needs none) without
  blocking compilation.

### Typed refusal codes

`REFUSED_INVALID_CLASS_IRI`, `REFUSED_MISSING_SUBJECT_MAP`, `REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY`,
`REFUSED_UNMAPPED_DATATYPE`, `REFUSED_AMBIGUOUS_RELATIONSHIP`, `REFUSED_INVALID_JOIN_CONDITION`,
`REFUSED_RELATIONSHIP_WITHOUT_PREDICATE`, `REFUSED_R2RML_JOIN_WITHOUT_IDENTITY`,
`REFUSED_UNPROVEN_EQUIVALENCE`, `REFUSED_SEMANTIC_TYPE_INVALID`,
`REFUSED_SEMANTIC_TYPE_ASH_MISMATCH`, `REFUSED_SEMANTIC_TYPE_REQUIRES_RESOURCE_PROJECTION`,
`REFUSED_SEMANTIC_ROUND_TRIP`, `REFUSED_UNSUPPORTED_SPARQL_FEATURE`.

### Benchmarks and explanatory docs

Real, reproducible benchmark numbers (compilation scaling, `AshR2RML.OBDA.InMemory` vs
Ontop+Postgres query latency) live in `bench/RESULTS.md`, generated by
`bench/compilation_and_rendering.exs` and `bench/obda_query_latency.exs`. No graph database
or engine outside AshR2RML's own supported stack (Ash, `Ash.DataLayer.Ets`, `AshPostgres`,
Ontop) is ever benchmarked — see `bench/README.md`. `documentation/topics/why-ashr2rml.md`
explains the product positioning grounded in those numbers.

### Standing vocabulary

`UNKNOWN`, `PARTIAL_ALIVE`, `ALIVE`, `BLOCKED`, `BUILD_BROKEN`, `UNSUPPORTED`, `REFUSED_<TYPE>`.
