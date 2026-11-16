# Release Manifest & Backlog Ticket Index: v26.11.11

**Milestone:** `v26.11.11`  
**Status:** READY / IMPLEMENTED  
**Component:** Documentation / Release Governance  
**Scope:** `docs/jira/v26.11.11/`  
**Release Tag:** `v26.11.11`  
**Admitted HEAD:** `a08afc027f222a5334a23878794c471f4a5d0f01`  
**Authority Ceiling:** `:NONE` (observe-only release qualification; live publication forbidden)

---

## 1. Executive Summary

Milestone `v26.11.11` delivers enterprise-grade encryption projections via AshCloak (`r2ml:encrypted` and `r2ml:cloakVault`), fail-closed refusal of unconsumed `r2ml:*` terms on property shapes (`@known_property_terms`), VM-independent deterministic action atom admission, multi-node policy AND-composition, refreshed ancestry court staleness allowlists, Hex release packaging certification, and a comprehensive 10-persona architectural review specification.

This index registers all milestone documents, architectural requirements, feature implementations, and release verification gates for production Hex readiness.

---

## 2. Document & Backlog Inventory

| Key | File | Title | Type | Status |
|---|---|---|---|---|
| `PRD-261111` | `PRD-v26.11.11.md` | Milestone Product Requirements Document | Epic PRD | IMPLEMENTED |
| `ARD-261111` | `ARD-v26.11.11.md` | Architecture Requirements Document | Epic ARD | IMPLEMENTED |
| `R2RML-261111-01` | `R2RML-261111-01-ash-cloak-encryption-projection.md` | AshCloak Encryption Projection (`r2ml:encrypted`, `r2ml:cloakVault`) | Feature | IMPLEMENTED |
| `R2RML-261111-02` | `R2RML-261111-02-property-shape-unknown-terms-refusal.md` | Property Shape Unknown Terms Refusal Gate | Integrity / Refusal | IMPLEMENTED |
| `R2RML-261111-03` | `R2RML-261111-03-deterministic-action-atom-admission.md` | Deterministic Action Atom Admission (No `to_existing_atom`) | Bug / Determinism | IMPLEMENTED |
| `R2RML-261111-04` | `R2RML-261111-04-declarative-policy-and-composition.md` | Declarative Policy AND-Composition for Discrete Policy Nodes | Feature / Security | IMPLEMENTED |
| `R2RML-261111-05` | `R2RML-261111-05-ancestry-court-staleness-allowlist.md` | Ggen Runtime Pin Ancestry Court Staleness Allowlist | Hygiene / Integrity | IMPLEMENTED |
| `R2RML-261111-06` | `R2RML-261111-06-hex-publish-readiness-verification.md` | Hex Package Build Verification & Release Policy Gate for v26.11.11 | Release Gate | VERIFIED |
| `R2RML-261111-07` | `R2RML-261111-07-ten-persona-architectural-review-specification.md` | Ten-Persona Architectural Review Specifications & Audit Governance | Audit / Review | ACTIVE |

---

## 3. Milestone Scope & Thematic Epics

1. **Cryptographic Protection & RDF Disclosure Boundaries (`R2RML-261111-01`, `02`)**:
   - Ingestion of `r2ml:encrypted` from SHACL property shapes and `r2ml:cloakVault` from node shapes into SemanticIR provenance.
   - Fail-closed admission: encryption requires vault specification; encrypted attributes cannot serve as identity keys.
   - Code generation injecting `AshCloak` Spark extension, `cloak do vault ... attributes [...] end`, and `public? false` on plaintext fields with `default_accept` for default actions.
   - Relational rendering: `encrypted_<attr>` emitted as `bytea` in SQL DDL and `:binary` in Ecto migrations.
   - Semantic boundary defense: encrypted attributes are strictly excluded from R2RML `PredicateObjectMap` listings, upholding the core security law: `RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`.
   - Fail-closed property shape validation: any unconsumed `r2ml:*` term triggers typed refusal `:REFUSED_SHACL_PROFILE_INCOMPLETE`.
2. **Determinism & Policy Security (`R2RML-261111-03`, `04`)**:
   - Deterministic action kind parsing via pattern matching (`"create"`, `"update"`, `"read"`, `"destroy"`) eliminating cold-VM atom table exhaustion/`ArgumentError` failures.
   - Multi-node policy conjunction: discrete `r2ml:policy` nodes compile into independent Ash policy blocks evaluated with logical AND in `Ash.can?`, preventing capability checks from bypassing tenant scope constraints.
3. **Integrity Closure & Ancestry Courts (`R2RML-261111-05`)**:
   - Filter allowlisted pin sites in `test/unit/ggen_runtime_ancestry_test.exs` so documented pins can be asynchronously updated without false-positive failures during court execution.
4. **Hex Packaging & Release Verification (`R2RML-261111-06`)**:
   - Validated package build with `mix hex.build` (1.36 MB, checksum `1951e2872d67b39dcc567cef983c4578deb3e40d6319f379fda3ac7a6308adba`, 263 distribution files).
   - Zero live publication doctrine (`mix hex.publish` reserved for automated CI tag push).
5. **Ten-Persona Architecture Review Specification (`R2RML-261111-07`)**:
   - Comprehensive audit specifications across 10 expert domains: Zach Daniel (Ash Framework), Joe Armstrong (OTP principles), José Valim (Elixir idioms), Chris McCord (Phoenix / Web channels), Pragmatic Programmers (Craftsmanship & DRY), Rich Hickey (Value-oriented systems), Martin Fowler (DDD & Bounded Contexts), Leslie Lamport (Formal safety invariants), Dan North (BDD & outside-in discovery), and Alan Kay (Autonomous cell messaging).

---

## 4. Verification Ladder

Independent verification of the v26.11.11 milestone is achieved by executing:

```bash
# 1. Formatting check
mix format --check-formatted

# 2. Strict compilation with warnings as errors
mix compile --warnings-as-errors

# 3. Encryption, policy AND-composition, and determinism test suite
mix test test/encrypted_and_policy_and_test.exs

# 4. Ancestry court verification
mix test test/unit/ggen_runtime_ancestry_test.exs

# 5. Consolidated ecosystem multi-extension test suite
mix test test/encrypted_and_policy_and_test.exs test/ontology_first_extensions_test.exs test/ontology_first_domains_test.exs test/ingestion_determinism_test.exs

# 6. Core test suite (excluding external JDBC/Docker services)
mix test --exclude external

# 7. Hex package construction & artifact integrity
mix hex.build
```
