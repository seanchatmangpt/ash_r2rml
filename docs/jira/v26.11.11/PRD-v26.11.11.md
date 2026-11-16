# PRD v26.11.11 — Milestone Product Requirements Document

**Title:** AshCloak Semantic Encryption, Refusal Hardening & Hex Publication  
**Status:** IMPLEMENTED / VERIFIED  
**Component:** `AshR2RML` Core, Ingestion, Admission, Semantic Extensions, Packaging  
**Scope:** Repository-wide milestone v26.11.11  
**Release:** `v26.11.11`  
**Repository:** `seanchatmangpt/ash_r2rml`  
**Owner:** AshR2RML Core Team  
**Admitted HEAD:** `a08afc027f222a5334a23878794c471f4a5d0f01`  
**Authority Ceiling:** `:NONE` (observe-only release qualification; live publication forbidden)

---

## 1. Product Outcome

Milestone `v26.11.11` enables downstream enterprise developers and autonomous code generators to:
1. **Declare Encrypted Attributes in SHACL**: Annotate sensitive fields via `r2ml:encrypted true` and specify `r2ml:cloakVault` on resource shapes, automatically synthesizing `AshCloak` configurations, `bytea` / `:binary` ciphertext database columns, private field visibility, and automatic exclusion from RDF publication.
2. **Fail-Closed Protection Against Configuration Errors**: Benefit from strict compile-time rejection of typographical errors or unrecognized `r2ml:*` predicates on property shapes via an exhaustive allowlist.
3. **Deterministic Clean-Room Compilation**: Rely on deterministic action atom parsing that functions flawlessly in fresh, cold BEAM instances without relying on pre-existing atom tables.
4. **Declarative Multi-Policy Authorization**: Specify discrete authorization policies in RDF shapes with guaranteed conjunctive (logical AND) evaluation in Ash.
5. **Ingest a Formally Audited Hex Package**: Consume an immutable Hex package release (`v26.11.11`) audited across 10 expert engineering disciplines (Ash Framework, OTP, Elixir idioms, Web channels, Craftsmanship, Simplicity, DDD, Formal invariants, BDD, and Autonomous messaging).

---

## 2. Problem Statement

Prior to v26.11.11:
- **Sensitive Data Exposure Risk**: Applications needing encrypted fields (PII, tokens, secrets) required manual post-generation `AshCloak` configuration. Accidental inclusion of these attributes in R2RML mappings risked exposing plaintext or ciphertext through SPARQL query endpoints or GraphQL projections.
- **Silent Dropping of Typographical Errors**: Unrecognized predicates under the `r2ml:` namespace on property shapes (e.g. `r2ml:encrpyted true`) were silently ignored during ingestion, giving developers a false impression that encryption or configuration was active.
- **Cold-VM Compilation Failures**: Action kind parsing relied on `String.to_existing_atom/1`, which crashed with an unhandled `ArgumentError` when running on freshly booted BEAM nodes where action atoms (e.g. `:destroy`) had not yet been interned.
- **Ambiguity in Multi-Policy Conjunction**: SHACL shapes declaring multiple policy nodes lacked explicit integration tests proving that Ash policy evaluation enforced logical AND conjunction across discrete nodes.
- **Ancestry Court False Positives**: Asynchronous documentation commit pins caused test failures when asserted against live HEAD without allowlisting.

---

## 3. Functional Requirements

### FR1. AshCloak Encryption Projection
- **FR1.1**: Ingest `r2ml:encrypted true` boolean literal from `sh:PropertyShape` into attribute provenance.
- **FR1.2**: Ingest `r2ml:cloakVault <VaultModule>` string/IRI from `sh:NodeShape` into resource provenance.
- **FR1.3**: Validate encryption admission invariants:
  - If an attribute has `:encrypted true` but the resource lacks `:cloak_vault`, return typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
  - If an attribute has `:encrypted true` and is also flagged `:identity_key true`, return typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
- **FR1.4**: Render `extensions: [AshCloak]` in the resource definition when encrypted attributes are present.
- **FR1.5**: Render `cloak do vault <VaultModule>; attributes [:<attr>, ...] end` in the resource body.
- **FR1.6**: Render plaintext encrypted attributes with `public?: false`.
- **FR1.7**: Render `default_accept [:<attr>, ...]` inside default actions (`create`, `update`) to permit input ingestion on private fields.
- **FR1.8**: In SQL DDL, emit `encrypted_<attr>` as `bytea` with appropriate nullability constraints.
- **FR1.9**: In Ecto migrations, emit `add :"encrypted_<attr>", :binary, null: <bool>, primary_key: false`.
- **FR1.10**: In `AshR2RML.Compiler` and `AshR2RML.Semantic.R2RML`, exclude all encrypted attributes from R2RML `PredicateObjectMap` generation, preserving the governing invariant `RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`.

### FR2. Property Shape Unknown Term Rejection
- **FR2.1**: Maintain an explicit compile-time allowlist `@known_property_terms` in `AshR2RML.Ingestion`.
- **FR2.2**: Inspect all predicates with prefix `r2ml:` on every property shape; if any predicate is not in `@known_property_terms`, reject ingestion with typed refusal `:REFUSED_SHACL_PROFILE_INCOMPLETE`.

### FR3. Deterministic Action Atom Admission
- **FR3.1**: In `AshR2RML.Ingestion.action_kind/2`, replace `String.to_existing_atom/1` with explicit pattern matching for `"create"` -> `:create`, `"update"` -> `:update`, `"read"` -> `:read`, `"destroy"` -> `:destroy`.
- **FR3.2**: Reject any unsupported action kind string with `:REFUSED_SHACL_PROFILE_INCOMPLETE`.

### FR4. Declarative Policy AND-Composition
- **FR4.1**: Parse multiple discrete `r2ml:policy` nodes from resource shapes into independent policy definitions.
- **FR4.2**: Render discrete `policy <action_type> do ... end` blocks in generated Ash resources.
- **FR4.3**: Verify via `Ash.can?` that caller authorization requires satisfying all policy blocks (logical AND), guaranteeing that capability checks cannot bypass tenant scoping.

### FR5. Hex Release Readiness & Ancestry Verification
- **FR5.1**: Synchronize version carrier to `26.11.11` in `mix.exs` and `ggen.toml`.
- **FR5.2**: Update `@staleness_allowlist` in `test/unit/ggen_runtime_ancestry_test.exs` and ensure allowlisted sites pass ancestry court checks.
- **FR5.3**: Verify package construction via `mix hex.build` with exit code 0, producing a valid tarball.
- **FR5.4**: Enforce zero unreceipted local publish policy (`mix hex.publish` reserved for automated CI tag push).

---

## 4. Acceptance Criteria

- [x] `r2ml:encrypted true` and `r2ml:cloakVault` parsed from SHACL Turtle profiles into SemanticIR.
- [x] Missing vault on encrypted attributes triggers typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [x] Encrypted identity keys trigger typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [x] Generated Ash resources include `AshCloak` extension and valid `cloak do ... end` DSL blocks.
- [x] Plaintext attributes are set to `public?: false` and accepted via `default_accept` in default actions.
- [x] SQL DDL emits `encrypted_<attr>` as `bytea` and Ecto migration emits `add :"encrypted_<attr>", :binary`.
- [x] R2RML compiler rejects encrypted attributes from predicate object maps (zero RDF disclosure).
- [x] Real Cloak AES-GCM round trip encrypts plaintext at rest and decrypts seamlessly through Ash calculations.
- [x] Unknown `r2ml:*` terms on property shapes fail closed with `:REFUSED_SHACL_PROFILE_INCOMPLETE`.
- [x] Action kinds parse deterministically in clean-room VMs without `String.to_existing_atom`.
- [x] Multi-node policies evaluate with logical AND semantics in `Ash.can?`.
- [x] `test/unit/ggen_runtime_ancestry_test.exs` passes with allowlist filtering.
- [x] `mix format --check-formatted` passes with 0 errors.
- [x] `mix compile --warnings-as-errors` passes with 0 warnings.
- [x] `mix test test/encrypted_and_policy_and_test.exs` passes with 7 tests, 0 failures.
- [x] `mix hex.build` succeeds with valid ~1.36 MB tarball and matching checksum.
- [x] Zero live publish commands (`mix hex.publish`) executed locally.

---

## 5. Definition of Done (DoD)

1. **Code & Test Complete**: All feature implementations and refusal gates implemented in `lib/` and exercised by comprehensive ExUnit suites in `test/`.
2. **Zero Regressions**: Consolidated 82-test Ash ecosystem suite passes with 0 failures.
3. **Strict Compilation**: `mix compile --warnings-as-errors` exits 0 with zero warnings.
4. **Documentation Sync**: `00-INDEX.md`, `ARD-v26.11.11.md`, `PRD-v26.11.11.md`, and 7 work orders created under `docs/jira/v26.11.11/`. `docs/sjira/v26.11.11/WORKGRAPH.ttl` synchronized.
5. **Changelog & Version Carriers**: `CHANGELOG.md` prepended with `## v26.11.11 (2026-11-11)`. `mix.exs` and `ggen.toml` synchronized to version `26.11.11`.
6. **Hex Package Verification**: `mix hex.build` verified and checksum documented in receipts.
