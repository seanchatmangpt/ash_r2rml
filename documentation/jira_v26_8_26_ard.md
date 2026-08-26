# AshR2RML v26.8.26 — Architecture Requirements Document

**Perspective:** Local DfCM Research & Manufacturing Engine — Architecture Requirements Pass
**Target Repository:** `ash_r2rml`
**Standing:** `PARTIAL_ALIVE`

See also: [`jira_v26_8_26.md`](jira_v26_8_26.md) for the feature roadmap and test suite
verification these decisions support.

---

## Part 1: Architecture Decisions & Invariants for v26.8.26

### 1. `AshR2RML.OBDA.InMemory` Is Data-Layer-Agnostic By Construction, Not By Accident

- **Decision:** `rows_for/3` (`lib/ash_r2rml/obda_in_memory.ex`) calls `Ash.read!/2`
  unconditionally, with no `AshR2RML.DataLayer.backend/1` check anywhere in the module. This
  was already true before this release; what changed is that it is now *verified* against real
  non-Ets data layers rather than merely inferred from reading the code.
- **Invariant Established:** any Ash resource, on any Ash data layer, that admits a real
  `AshR2RML.Mapping.Resource` can be materialized and SPARQL-queried through `InMemory` with
  zero code changes. Verified by `test/obda_in_memory_other_data_layers_test.exs` against real
  `AshCsv.DataLayer` (a real CSV file on disk, `File.rm`-cleaned per test) and
  `AshCubDB.DataLayer` (a real CubDB store, unique tmp directory per resource) resources --
  both create real rows via `Ash.create!/2` and read them back via `InMemory.materialize/3` and
  `InMemory.query/4`, asserting real triples and real SPARQL binding rows.
- **Corollary invariant**: `AshR2RML.DataLayer.backend/1` returning `:unknown` for a data layer
  it doesn't specifically name is not a defect -- it only gates `table_name/1`'s
  Postgres/Ets-specific resolution logic and `AshR2RML.Security.sanitize_mapping/2`'s
  `:postgres`-only structural exclusion (see decision 3 in `jira_v26_8_25_ard.md`). It never
  gates `InMemory`, because `InMemory` doesn't consult it.

### 2. `AshR2RML.Ggen.compile_api_bundle/2` — Additive Bundle, Not a Core-Path Change

- **Decision:** `AshR2RML.Semantic.Ash.render/2` (`lib/ash_r2rml/semantic_renderers.ex`) adds an
  `opts` parameter (`graphql:`/`json_api:` booleans, default `false`/`false`) to the existing
  `render/1`, which now delegates with `opts \\ []` -- every existing call site
  (`render(ir)`) is untouched and produces byte-identical output. `AshR2RML.Ggen.compile_api_bundle/2`
  (`lib/ash_r2rml/ggen.ex`) is a new function, not a modification of `compile_bundle/1`; it
  reuses `AshR2RML.Admission.admit/1` directly, mirroring `AshR2RML.Compiler`'s own internal
  flow (`Admission.admit -> Semantic.Ash.render`) rather than introducing a parallel admission
  path.
- **Invariant Established:** the derived `graphql do type ... end` / `json_api do type ... end`
  block's type name comes from the same `resource.module` identity that already drives
  `class_iri`/`table_name` in the `r2rml` block -- one identity, multiple projections, per this
  project's own semantic-correspondence law (`AGENTS.md`). Verified as genuinely compilable DSL
  (not string-plausible text) by `test/ggen_api_bundle_test.exs`'s real `Code.eval_string/1` +
  `Spark.extensions/1` + `AshGraphql.Resource.Info.type/1`/`AshJsonApi.Resource.Info.type/1`
  round trip.
- **Dependency architecture, explicit tradeoff named**: `ash_graphql`/`ash_json_api` are
  `:test`-only (`mix.exs`). This was a deliberate correction mid-session: the first instinct
  (add them as real deps so AshR2RML could "support" GraphQL/JSON:API) was wrong, because Ash
  extensions already compose independently -- any consumer resource can add
  `AshGraphql.Resource`/`AshJsonApi.Resource` directly with zero AshR2RML involvement. Making
  them real dependencies would force every AshR2RML consumer to pull in Absinthe/Phoenix/
  JSON:API stacks whether or not they use either. `:test`-only preserves the verification value
  (the emitted DSL genuinely compiles) without that cost.

### 3. Two-Direction Security Asymmetry Pattern, Now Confirmed Twice More

- **Decision/finding, not yet code**: `AshR2RML.Security` (`lib/ash_r2rml/security.ex`) closes
  exactly one instance of a general pattern -- an Ash extension enforcing its guarantee via a
  query-time Ash construct (a preparation, a policy check, a lazy calculation) rather than a
  real database-level construct (Postgres RLS, a filtered view, a CHECK constraint) will always
  produce an asymmetry between `AshR2RML.OBDA.InMemory` (Ash-mediated, inherits the guarantee
  for free) and `AshR2RML.OBDA.Ontop` (JDBC-direct, structurally blind to anything Ash computed
  in the application layer). v26.8.26's research confirmed two more real instances of this
  pattern, in *both* directions:
  - **`ash_archival`** (same direction as the field-policy gap): Ontop over-exposes (archived
    rows visible), InMemory is safe (Ash's own `is_nil(archived_at)` preparation excludes them
    for free via `Ash.read!/2`).
  - **`ash_cloak`** (opposite direction — new, more severe): InMemory can over-expose (a
    `decrypt_by_default`-configured attribute's calculation loads automatically on plain
    `Ash.read!/2`, materializing plaintext into the RDF graph), while Ontop is safe *only by
    architectural accident* (it can only ever see the raw `encrypted_<name>` ciphertext
    column, having no Cloak.Vault key material anywhere in its JDBC path).
- **Invariant NOT yet established (open, ticketed below)**: neither of these two is fixed in
  this release. `AshR2RML.Security.sanitize_mapping/2`'s current scope is field policies on
  `AshPostgres.DataLayer`-backed resources only; it does not detect `ash_archival` state or
  `ash_cloak`-backed attributes on any backend. Documenting the *pattern* (query-time-Ash-only
  guarantee ⇒ asymmetric OBDA exposure) here is deliberate, so the next two fixes generalize the
  existing `sanitize_mapping/2` machinery rather than each reinventing detection logic.

---

## Part 2: Jira Ticket Backlog (`docs/jira/v26.8.26/`)

### Ticket 1: `R2RML-109` — Close the `ash_cloak` Plaintext-Leak Gap in `AshR2RML.OBDA.InMemory`

- **Type:** Security / Architecture Gap
- **Priority:** **Highest** (more severe than the field-policy gap this generalizes from: it
  leaks plaintext through the "safe" surface, not the "already assumed risky" one)
- **Component:** `AshR2RML.OBDA.InMemory` / `AshR2RML.Security`
- **Description:**
  A resource with an `ash_cloak`-encrypted, R2RML-mapped attribute configured with
  `decrypt_by_default` (a normal, documented, easily-reached-for DSL option — not an edge case)
  will have that attribute's plaintext silently materialized into the RDF graph by
  `AshR2RML.OBDA.InMemory.materialize/3`, because `Ash.read!/2` with no special `read_opts`
  already loads the decryption calculation for any `decrypt_by_default`-listed attribute. This
  is real and reachable through unremarkable configuration, not a contrived edge case.
- **Acceptance Criteria:**
  1. Add real detection: given an Ash resource module, determine which attributes are backed by
     an `ash_cloak` `encrypted_<name>` renamed attribute + matching decryption calculation
     (read the real `ash_cloak` transformer/DSL introspection API to do this correctly, not by
     guessing at naming conventions — verify against `ash_cloak`'s real `Info` module if one
     exists).
  2. Extend `AshR2RML.Security` (or a sibling module) so any such attribute is excluded from
     `AshR2RML.OBDA.InMemory` materialization by default — either by stripping it from the
     mapping before materialization (matching `sanitize_mapping/2`'s existing pattern) or by
     forcing `Ash.read!/2`'s `read_opts` to never load that calculation regardless of the
     resource's own `decrypt_by_default` setting. This must apply to **any** backend (unlike
     the field-policy fix, which is `:postgres`-only) — Cloak is orthogonal to which data layer
     stores the ciphertext.
  3. Add `ash_cloak` as a `:test`-only dependency (matching `ash_postgres`/`ash_graphql`/
     `ash_json_api`'s existing pattern) and a real end-to-end test: a real `ash_cloak`-backed
     resource with `decrypt_by_default` set, real `Ash.create!` with a real secret value, and an
     assertion that `AshR2RML.OBDA.InMemory.materialize/3` does **not** contain the plaintext
     anywhere in the resulting `RDF.Graph`.
  4. Document the fix and its scope difference from the `:postgres`-only field-policy fix in
     `AGENTS.md`'s "Query backend security" section.

### Ticket 2: `R2RML-110` — Close the `ash_archival` Soft-Delete Exposure Gap for Ontop/Postgres

- **Type:** Security / Correctness Gap
- **Priority:** High
- **Component:** `AshR2RML.Compiler` / R2RML mapping generation for `AshPostgres.DataLayer`
- **Description:**
  A resource using `ash_archival` (soft deletion via an Ash-level `is_nil(archived_at)` query
  preparation, with no Postgres-side enforcement — confirmed against the real extension's
  documented mechanism) will have archived rows correctly excluded from
  `AshR2RML.OBDA.InMemory` (which goes through `Ash.read!/2` and inherits the preparation), but
  fully exposed to a direct Ontop/JDBC query against the raw table, since the R2RML mapping's
  logical table has no equivalent filter.
- **Acceptance Criteria:**
  1. Detect `ash_archival` on an `AshPostgres.DataLayer`-backed resource being compiled (real
     introspection, not attribute-name guessing — verify `ash_archival`'s own `Info` module).
  2. When detected, either (a) inject an `archived_at IS NULL` condition into the generated
     R2RML mapping's logical table (an `rr:SQLQuery` rather than a plain `rr:tableName`,
     mirroring how a filtered view would work), or (b) refuse compilation for that resource
     under `storage_backend: :postgres` with a typed refusal explaining the gap, if (a) is not
     tractable in the current renderer — pick whichever is honestly achievable, document the
     choice.
  3. Add a real end-to-end test: real `ash_archival`-backed `AshPostgres.DataLayer` resource
     (reusing the `ash_postgres`-as-`:test`-dependency pattern from `R2RML-105`), a real
     archived row, and an assertion that either the generated R2RML mapping excludes it or
     compilation is explicitly refused — not silently exposed.

### Ticket 3: `R2RML-111` — `ash_paper_trail` → PROV-O Auto-Derivation

- **Type:** Feature / Semantic Enrichment
- **Priority:** Medium
- **Component:** New module, analogous to `lib/ash_r2rml/provenance.ex`
- **Description:**
  `ash_paper_trail`'s Version resource (one row per tracked `create`/`update`/`destroy` action)
  maps cleanly onto `prov:Activity` with `prov:generatedAtTime` (`version_inserted_at`) and
  `prov:generated`/`wasGeneratedBy` (`version_source`), and — when `store_action_name?`/actor
  tracking are enabled — `prov:wasAssociatedWith` via the actor's own IRI. The `changes` map
  (three possible shapes depending on `change_tracking_mode`) has no native PROV-O equivalent
  and needs a deliberate representation decision, not a mechanical translation.
- **Acceptance Criteria:**
  1. Add `ash_paper_trail` as a real dependency (not `:test`-only — this is intended as a real
     consumer-facing feature, unlike the GraphQL/JSON:API verification-only deps) with a
     documented required configuration (`store_action_name?: true`, `reference_source?: true`,
     an actor relationship configured) for the PROV-O-relevant fields to be present.
  2. Verify the exact actor-tracking DSL shape directly against `ash_paper_trail`'s real source
     (flagged as unconfirmed in this release's research) before implementing
     `wasAssociatedWith`.
  3. Implement `AshR2RML.Mapping.PaperTrailProvenance` (or similar) producing the same
     `PredicateObjectMap`/`ObjectMap` structs `lib/ash_r2rml/provenance.ex` already produces,
     feeding the existing R2RML/PROV-O rendering path — no new rendering engine.
  4. Make an explicit, documented decision for the lossy `changes`-map representation (custom
     vocabulary extension vs. per-attribute reification vs. omission) rather than leaving it
     implicit.

### Ticket 4: `R2RML-112` — Decide `ash_events` vs. `AshR2RML.Telemetry.OCEL2`

- **Type:** Architecture Decision / Technical Debt
- **Priority:** Medium
- **Component:** `AshR2RML.Telemetry.OcelAshEmitter` / `AshR2RML.Telemetry.OCEL2`
- **Description:**
  `AshR2RML.Telemetry.OcelAshEmitter`'s `:telemetry`-based capture and raw NDJSON-append
  storage (`priv/ocel/ash-actions.ndjson`, no locking, no schema enforcement at write time)
  duplicates what `ash_events` does more robustly at the single-resource level (transactional
  Postgres storage, versioned schema, real action-replay that rebuilds actual resource rows —
  which `OCEL2.reconstruct_from_events/1` does not do; it only rebuilds an in-memory reporting
  projection). `OCEL2`'s multi-object (E2O/O2O) and process-mining (conformance-checking
  against POWL nets/workflow nets) capabilities have no `ash_events` equivalent and are
  genuinely differentiated.
- **Acceptance Criteria:**
  1. A real design decision, written down: adopt `ash_events` as the durable capture+replay
     substrate for per-resource events (replacing `ocel_ash_emitter.ex`'s NDJSON plumbing),
     keep `ocel_v2.ex` unchanged as the OCEL2-conformant export/validation/conformance-checking
     layer, and write one adapter translating `ash_events` records (plus the still-needed
     Reactor-step telemetry for multi-object semantics) into OCEL2 `Event`/`Object` structs.
  2. Before implementing: confirm whether `OcelAshEmitter.attach!`/`TelemetryLogger` are
     intended to be always-on in production or Reactor/test-pipeline-scoped by design (this
     research could not find an `application.ex` wiring either into a global supervisor — flag
     this to whoever owns the telemetry architecture rather than assume).
  3. If adopted: real end-to-end test that a real `ash_events`-captured action sequence,
     translated through the adapter, produces `AshR2RML.Telemetry.OCEL2.validate/1`-conformant
     output and round-trips through `reconstruct_from_events/1` correctly.

---

## Informational: Prior Art (No Action Item)

A real, thorough web/GitHub search found no public prior art combining Ash/Reactor/Spark with
R2RML/RDF/SPARQL/SHACL — `ash_r2rml` appears first-of-kind in this specific combination, as far
as public search results show (not a claim of certainty; private/unpublished work could exist).
The closest adjacent prior art is **Grax** (`rdf-elixir/grax`), an Ecto-schema-like RDF graph
data mapper — conceptually the nearest thing to "Ecto for RDF" in the Elixir ecosystem, but a
data-mapper library, not an Ash-style framework that auto-derives a query/API surface the way
`AshGraphql`/`AshJsonApi` do. Worth being aware of; no integration action identified.
