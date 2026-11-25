<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# AshR2RML Agent Operating Contract

This contract governs the repository unless a deeper `AGENTS.md` narrows a subtree. Live tree evidence outranks stale prose. Nested doctrine may tighten constraints but may not silently weaken evidence, semantic correspondence, authority, replay, or publication law.

## Product invariant

AshR2RML is the W3C R2RML/RDF semantic-mapping layer for Ash Framework. It is not an `Ash.DataLayer`, graph database, triplestore, proprietary query engine, or replacement persistence layer.

Ash resource metadata and explicit semantic annotations must normalize into one deterministic mapping IR before verification/rendering.

Ownership remains explicit: Ash owns resource/action/domain semantics; relational and other Ash data layers own persistence; AshR2RML owns semantic metadata, introspection, compile-time validation, normalized IR, and R2RML rendering; `AshR2RML.OBDA.InMemory` owns in-process RDF materialization/SPARQL execution over real Ash reads from any supported Ash data layer; Do not blur these boundaries.

## Preserve → Fence → Calculus

Resolve repo/ref/base to an exact commit and read applicable root+nested doctrine, README/docs, `mix.exs`, lockfile, CI, release workflow, generators, and test layout. Preserve public DSL/API, normalized IR, semantic identity, datatype law, correspondence, typed refusals, generated/manual ownership, and reversible alternatives. Apply Chesterton's fence before removing an existing boundary. One failed edge is topology, not graph failure.

`A = μ(O*)`; `R = receipt(A)`. Separate `SELECT`, `CONSTRUCT`, `DO`. Model/planner/generator/proof/hook output has no ambient execution authority. Consequential execution uses the repository's admitted Ash/runtime boundary and must be receipted.

## Evidence / standing

Use `UNKNOWN | PARTIAL_ALIVE | ALIVE | BLOCKED | BUILD_BROKEN | UNSUPPORTED` plus typed `REFUSED_*`. `ALIVE` requires observed execution against the exact admitted subject. Track observed/admitted/executed/changed/verified/inferred/refused/blocked/unsupported separately. Inspection is not execution; compile metadata is not an executed mapping; emitted Turtle is not proven semantic equivalence; a workflow is not a successful run.

## Semantic correspondence law

Preserve the same admitted class, attribute/property, relationship/join, subject identity, datatype, cardinality, and graph semantics across Ash, relational, IR, R2RML, SHACL/profile, and OBDA projections. Normalize to IR first, verify second, render third. Never generate R2RML directly from scattered ad-hoc inspection paths.

Database identity and RDF identity are distinct. Subject templates/columns/constants/blank nodes must be explicit; every template field resolves to a mapped attribute; reference joins target stable unique identities. Never derive semantic IRIs silently from module names or internal row IDs.

Datatype conversion must be explicit and lossless. Unknown Ash types must not silently degrade to strings. Preserve typed semantic refusals for invalid IRIs, missing subject maps, non-unique identity, unmapped datatypes, ambiguous relationships, invalid joins, missing predicates/identity, unproven equivalence, invalid semantic types, type/Ash mismatch, projection requirements, unsupported SPARQL features, and failed semantic round trips. Compile-time DSL violations fail at compile time; runtime APIs return the repository's typed refusal structure (`{:error, %AshR2RML.Refusal{}}`).

The concrete correspondence table and code-level reference for the above live in [Concrete Reference](#concrete-reference) below — this section states the law; that section names the exact modules/functions that implement it.

## Query backend security

Semantic publication has its own authority boundary. **Readable by an Ash process is not equivalent to admitted for RDF publication.** The governing invariant is `RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`.

`AshR2RML.OBDA.InMemory` is Ash-mediated (`Ash.read!/2`), so denied fields (`%Ash.ForbiddenField{}`) are omitted and row-derived IRIs are validated or percent-encoded. That is necessary but not sufficient: an Ash extension can replace an admitted attribute with a derived field that an ordinary read loads automatically. `ash_cloak` is the observed falsifier — it replaces a cloaked attribute with a sensitive decrypting calculation under the same public name, and `decrypt_by_default` causes ordinary reads to carry plaintext. Therefore `AshR2RML.Security.sanitize_in_memory_mapping/2` is an obligatory pre-materialization admission transform. Any mapped scalar name that no longer resolves through `Ash.Resource.Info.attribute/2` is removed before graph construction and recorded in `mapping.metadata[:in_memory_non_attribute_excluded_attributes]`. When the subject map itself is not admissible (placeholder or column is not a real, non-cloaked attribute), `sanitize_in_memory_mapping/2` raises `ArgumentError` carrying the refusal code instead of rewriting. The typed-refusal path is `AshR2RML.Security.admit_in_memory_mapping/3`, which returns `{:error, %AshR2RML.Refusal{}}` for that case and for subject or graph maps reading a protected (`sensitive?: true`) attribute unless `allow_sensitive: true`; `sanitize_in_memory_mapping/2` calls it with `allow_sensitive: true`, leaving the protected-attribute decision to `OBDA.InMemory`. Calculations, aggregates, or extension-manufactured fields have no ambient RDF-publication authority merely because their values are loaded into the record struct.

`AshR2RML.Security.sanitize_mapping/2` (wired into `AshR2RML.Compiler.compile_resources/1`) exists so that rendered R2RML does not leak field-policy-gated attributes: rendered R2RML is consumed by readers that bypass Ash and have no actor with which to enforce a `field_policy`. For `AshPostgres.DataLayer`-backed resources it strips any R2RML-mapped attribute that carries an explicit `field_policy` before rendering, recording the exclusion in `mapping.metadata[:field_policy_excluded_attributes]`. For every data layer it also strips mapped attributes marked `sensitive?: true` (`mapping.metadata[:sensitive_excluded_attributes]`). This is a structural exclusion, not a refusal gate: it never blocks compilation, and it deliberately does not attempt to distinguish an unconditional `authorize_if always()` policy from a genuinely conditional one.

## Unreleased handoff contract (frozen for ash_graphlaw / ash_affidavit)

Do not change without a CHANGELOG "Unreleased" entry: deterministic R2RML Turtle, canonical
N-Quads (`AshR2RML.NQuads`), invertible subject codec (`AshR2RML.Subject`), and the
`AshR2RML.OBDA.Result` digest framing (length-prefixed r2rml, sparql, bindings).

## Work / verification

Follow `parse → orient → resolve → materialize → read doctrine → inspect → admit/refuse → diagnose/repair → construct → actuate → receipt → replay → standing`. Prefer the existing lawful path and smallest coherent diff. No fabricated evidence, weakened tests, acceptance mocks for real DB/OBDA claims, unrelated refactors, or unresolved production placeholders.

Acceptance precedence: exact user behavior/command → live documented repository command → narrowest equivalent. Discover the current ladder from `mix.exs`, tests, CI, and release workflow at the admitted SHA rather than freezing it here. Preserve the intended progression across formatting/compilation, pure IR tests, adversarial/refusal tests, enterprise/policy cases, OBDA integration (in-process `AshR2RML.OBDA.InMemory`, the sole OBDA backend), package build, and release gates when those surfaces exist. CI supplements local execution; it is not truth.

As of this writing that ladder is: `mix format --check-formatted` → `mix compile --warnings-as-errors` → `mix test test/unit/` → `mix test test/adversarial/ test/negative/` → `mix test test/fortune5/` → full `mix test` (plus `mix test --include sqlite`; the postgres tier runs with `--include postgres` and `ASH_R2RML_POSTGRES_URL` set) → `mix dialyzer` → `mix hex.build` → `bin/mutation-court` → tag `v*`, which triggers CalVer publication to Hex.pm (`.github/workflows/release.yaml`). Re-derive this from the repository rather than trusting it once it goes stale.

## GitHub / receipt

Never silently move the admitted base. Unless explicitly instructed otherwise: purpose branch, intentional commit, non-force push, draft PR, no merge. Final receipt identifies repo/base/tree, O/O*, transports/failures, changed/generated surfaces, commands/exits, verification ladder, receipt/replay, branch/SHA/PR, semantic standing, and falsifiers.

---

## Concrete Reference

The sections above are the durable process/evidence contract. This section is the current
code-level reference implementing it — re-verify against the live tree before trusting it,
per "live tree evidence outranks stale prose" above.

### Architecture at a glance

```text
Ash.Resource + r2rml/rdf DSL → AshR2RML.Mapping (IR) → Relational DB + R2RML (W3C Turtle)
                                                     → AshR2RML.OBDA.InMemory (Ash read, actor/tenant)
```

All compilation surfaces converge on: `AshR2RML.Mapping.{Resource, SubjectMap,
PredicateObjectMap, ReferenceObjectMap, JoinCondition, Datatype, GraphMap}`.

Scope (v26.11.24): ontology-first ingestion, ggen packs, GraphQL, Reactor, OCEL telemetry,
knowledge hooks, VKG, federation, DfCM and production admission were removed; recover them from
commit `5defc87` if needed.

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
  use Ash.Resource, extensions: [AshR2RML.Resource]

  r2rml do
    class "https://schema.org/Person"
    subject do
      template "urn:uuid:{id}"
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

### Query-execution backend

- **`AshR2RML.OBDA.InMemory`** materializes resources from any real Ash data layer reachable by
  `Ash.read!/2` into a real `RDF.Graph`, after `sanitize_in_memory_mapping/2` closes derived-field
  disclosure, then runs full SPARQL (`SELECT`/`ASK`/`CONSTRUCT`/`DESCRIBE`) through `AshR2RML.SPARQL.Local`/`SPARQL.ex`.
  Supports `materialize_many/2`/`query_many/3` for cross-resource joins via `reference_object_maps`,
  including composite-key (multi-column) `rr:joinCondition`s; a `:join_table` many-to-many shape is an explicit typed refusal, not a silent omission.
  `allow_sensitive: true` opts into materializing `sensitive?: true` attributes; the default refuses instead.
- **`AshR2RML.Compiler.compile/2`** compiles resources (or domains) into a `Mapping.Bundle`; its
  second argument is reserved and currently ignored.

### Subject module contract

`AshR2RML.Subject` is pure and template-only. `to_iri/2` percent-encodes attribute values
(`URI.encode/2` with `URI.char_unreserved?/1`, byte-identical to `OBDA.InMemory`) into the
subject template; `from_iri/2` inverts it and refuses unless the captured values re-encode to
the same IRI. `iri_only?/1` / `check_iri_only/1` admit only `:iri` subjects with no
`:blank_node` term map. Non-template strategies and non-invertible templates refuse (typed
`%AshR2RML.Refusal{}`, e.g. `:UNSUPPORTED_TERM_TYPE`).

### Domain-level compile

`AshR2RML.Compiler.compile_resources/1` (and `compile/2`) accept `Ash.Domain` modules mixed with
resources. A domain expands to its resources carrying the AshR2RML extension (deduplicated); a
domain with none refuses `REFUSED_MISSING_SUBJECT_MAP`.

### OBDA.InMemory option contract

Read options `:actor`, `:tenant`, `:authorize?`, `:context`, `:domain`, `:action` flow to
`Ash.read`. `authorize?` defaults to `true`. Guard options are consumed before the read and
fail closed with a typed refusal:

- `allow_unauthorized: true` is required to pass `authorize?: false`.
- `require_authorizer: true` refuses a resource without `Ash.Policy.Authorizer`.
- `require_tenant: true` refuses a multitenant resource read without `:tenant`.

`allow_sensitive` and `previous_graph` are separate materialization options.

### Canonical ordering

`query/4` and `query_many/3` sort `SELECT` rows canonically when the query has no `ORDER BY`
(independent of data-layer scan order); with `ORDER BY` the engine order is preserved. Result
hashes use `AshR2RML.SPARQL.Result.hash_rows/1` (multiset-normalized, deterministic term
encoding, SHA-256 hex).

### SPARQL.Protocol private-network guard

`AshR2RML.SPARQL.Protocol.query/3` accepts only `http`/`https` endpoints with a host, and
refuses private-network hosts with `REFUSED_INVALID_FEDERATION_ENVIRONMENT` unless
`allow_private_network: true` (default `false`). Other options: `:timeout`, `:max_rows`.

### Typed refusal codes

`REFUSED_INVALID_CLASS_IRI`, `REFUSED_MISSING_SUBJECT_MAP`, `REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY`,
`REFUSED_UNMAPPED_DATATYPE`, `REFUSED_AMBIGUOUS_RELATIONSHIP`, `REFUSED_INVALID_JOIN_CONDITION`,
`REFUSED_RELATIONSHIP_WITHOUT_PREDICATE`, `REFUSED_R2RML_JOIN_WITHOUT_IDENTITY`,
`REFUSED_UNPROVEN_EQUIVALENCE`, `REFUSED_UNSUPPORTED_SPARQL_FEATURE`,
`REFUSED_INVALID_FEDERATION_ENVIRONMENT`, plus `:UNSUPPORTED_TERM_TYPE` (unprefixed).

Mapping-shape codes: `REFUSED_INVALID_LOGICAL_TABLE`, `REFUSED_UNKNOWN_ATTRIBUTE`,
`REFUSED_INVALID_TERM_MAP`, `REFUSED_INVALID_GRAPH_MAP`, `REFUSED_NON_LITERAL_DATATYPE`,
`REFUSED_RELATIONSHIP_TARGET_UNMAPPED` (relationship target resource has no R2RML mapping).

Policy, generation and conflict codes: `REFUSED_SENSITIVE_ATTRIBUTE_MATERIALIZATION`
(a sensitive attribute would be materialized), `REFUSED_MANIFEST_GENERATION` (manifest
generation failed), `REFUSED_CHANGESET_CONFLICT` (conflicting changeset).

Security, type and option codes: `REFUSED_ENCRYPTED_ATTRIBUTE_PROJECTION` (AshCloak attribute
would be projected in plaintext; admit only as an opaque `urn:sha256:` pointer),
`REFUSED_PRIVATE_DATA_LAYER` (`OBDA.query/3` on a `private?: true` ETS resource),
`REFUSED_INVALID_OPTION` (worker `:timeout_ms` / `:max_heap_words` not a positive integer),
`UNSUPPORTED_ASH_TYPE` (array, NewType cycle, `Ash.Type.Range`, or no admitted datatype contract).

Resource-bound code: `REFUSED_RESOURCE_BOUND` (a request, row or size bound was exceeded;
fail closed, never truncate silently).

OBDA runtime codes (`AshR2RML.Error`): `REFUSED_RESULT_LIMIT_EXCEEDED`,
`REFUSED_TRIPLE_LIMIT_EXCEEDED`, `REFUSED_MEMORY_LIMIT_EXCEEDED`, `REFUSED_QUERY_TIMEOUT`,
`REFUSED_MISSING_TENANT`, `REFUSED_UNAUTHORIZED`, `REFUSED_READ_FAILED`,
`REFUSED_WORKER_CRASHED`; subject codes `REFUSED_MISSING_SUBJECT_KEY`,
`REFUSED_INVALID_SUBJECT_IRI`, `REFUSED_NON_INVERTIBLE_TEMPLATE`. `OBDA.InMemory` is the sole
OBDA backend.
