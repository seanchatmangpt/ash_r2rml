# ARD v26.11.11 — Architecture Requirements Document

**Title:** AshCloak Encryption Projection, Refusal Gates & Determinism Invariants  
**Status:** IMPLEMENTED / ADMITTED  
**Component:** `AshR2RML` Semantic Compiler, Semantic.Extensions, Admission, Ecto, SQL, Packaging  
**Scope:** Architecture and structural invariants for milestone v26.11.11  
**Release:** `v26.11.11`  
**Repository:** `seanchatmangpt/ash_r2rml`  
**Admitted HEAD:** `a08afc027f222a5334a23878794c471f4a5d0f01`  
**Authority Ceiling:** `:NONE` (observe-only execution; no DO; no live publication)

---

## 1. Architectural Objective

Preserve the fundamental product invariant of AshR2RML:
> **AshR2RML is the W3C R2RML/RDF semantic-mapping and DfCM type-compiler layer for Ash Framework. It is not an `Ash.DataLayer`, graph database, triplestore, proprietary query engine, or replacement persistence layer.**

The v26.11.11 architecture reinforces and formalizes the governing query backend security invariant:
> **`RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`**

Downstream applications storing personally identifiable information (PII) or confidential credentials in relational databases require transparent at-rest encryption while simultaneously guaranteeing that RDF/SPARQL exposure layers cannot leak plaintext or ciphertext.

By synthesizing `AshCloak` configurations directly from SHACL shapes (`r2ml:encrypted true` and `r2ml:cloakVault`), refusing unconsumed `r2ml:*` property terms fail-closed, ensuring cold-VM deterministic action atom parsing, and enforcing logical AND conjunction across discrete policy nodes, v26.11.11 ensures end-to-end cryptographic and semantic safety.

---

## 2. Component Architecture & Ingestion Flow

```text
[SHACL Node & Property Shapes (Turtle)]
                 │
                 ▼
     [AshR2RML.Ingestion]
        ├─ Parse r2ml:encrypted (property) & r2ml:cloakVault (node)
        ├─ Filter r2ml:* terms against @known_property_terms (reject unknown)
        └─ Map action kinds: "create"|:"create", "update"|:"update", etc.
                 │
                 ▼
     [AshR2RML.SemanticIR]
        ├─ Resource provenance carries :cloak_vault
        └─ Attribute provenance carries :encrypted true
                 │
                 ▼
     [AshR2RML.Admission & Semantic.Extensions]
        ├─ Verify vault presence: encrypted attribute requires r2ml:cloakVault
        ├─ Verify identity key: encrypted attribute cannot be identity key
        └─ Retain provenance metadata
                 │
                 ├───────────────────────────────┬───────────────────────────────┐
                 ▼                               ▼                               ▼
    [Ash Resource AST Rendering]       [Relational DDL & Ecto]          [R2RML Mapping & IR]
  - Inject extensions: [AshCloak]   - SQL: quote("encrypted_"<>n)   - Reject encrypted attrs
  - Emit cloak do vault ... end       bytea nullability               from PredicateObjectMaps
  - Plaintext: public?: false       - Ecto: add :"encrypted_"<>n,   - Preserves invariant:
  - Default actions: default_accept   :binary, null: bool              RDF disclosure ⊆ Ash
```

### Component Roles

| Component | Modules | Architectural Responsibility |
|---|---|---|
| **Ingestion** | `AshR2RML.Ingestion` | Extracts `r2ml:encrypted` and `r2ml:cloakVault`. Enforces fail-closed refusal of unconsumed `r2ml:*` terms on property shapes. Maps action kinds deterministically. |
| **Admission** | `AshR2RML.Admission`, `AshR2RML.Semantic.Extensions` | Validates presence of `r2ml:cloakVault` when attributes are encrypted. Rejects encrypted identity keys. |
| **Semantic Extensions** | `AshR2RML.Semantic.Extensions` | Computes encrypted attribute lists, renders `cloak do ... end` DSL blocks, renders `default_accept` lists for default actions. |
| **Code Generation** | `AshR2RML.SemanticRenderers` | Injects `AshCloak` into Spark extension lists. Emits `public?: false` for plaintext encrypted attributes. Generates migration code. |
| **Relational DDL** | `AshR2RML.Semantic.SQL`, `AshR2RML.Semantic.Ecto` | Emits `encrypted_<name>` as `bytea` in SQL DDL and `:binary` in Ecto migrations. |
| **R2RML Compiler** | `AshR2RML.Compiler`, `AshR2RML.Semantic.R2RML` | Filters out encrypted attributes from predicate-object mappings, ensuring zero RDF leakage. |
| **Packaging & Courts** | `AshR2RML.GgenRuntimeAncestryTest`, `mix.exs` | Enforces pin ancestry against live HEAD; validates hermetic Hex tarball construction. |

---

## 3. Core Architectural Invariants

### Invariant 1: AshCloak Cryptographic Projection & Disclosure Exclusion
1. **Vault Requirement**: An attribute declaring `r2ml:encrypted true` strictly requires `r2ml:cloakVault <VaultModule>` on the enclosing resource shape. Absence of a vault triggers a typed refusal (`:REFUSED_UNPROVEN_EQUIVALENCE`).
2. **Identity Key Exclusion**: An attribute flagged as an `identityKey` (`r2ml:identityKey true`) cannot be marked `r2ml:encrypted true`. Attempting to encrypt an identity key fails closed with `:REFUSED_UNPROVEN_EQUIVALENCE`.
3. **Plaintext Visibility**: The logical plaintext attribute is rendered with `public?: false` in the generated Ash resource.
4. **Action Input Ingestion**: Default actions (`create`, `update`) append `default_accept [:<encrypted_attr>, ...]` so that private ciphertext fields can ingest caller arguments during standard changeset processing.
5. **Ciphertext Persistence**:
   - In SQL DDL (`AshR2RML.Semantic.SQL`), the physical column is named `encrypted_<name>` and typed `bytea`.
   - In Ecto migrations (`AshR2RML.Semantic.Ecto`), the column is emitted as `add :"encrypted_<name>", :binary`.
6. **RDF Disclosure Exclusion**:
   - `AshR2RML.Compiler` and `AshR2RML.Semantic.R2RML` filter out all attributes where `AshR2RML.Semantic.Extensions.encrypted?/1` is `true`.
   - Neither plaintext nor ciphertext is mapped into R2RML `rr:PredicateObjectMap` graphs.
   - Core theorem: `RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`.

### Invariant 2: Property Shape Unknown Term Rejection (Zero Silent Dropping)
- Ingestion enforces a strict allowlist `@known_property_terms`:
  `~w(ashName columnName postgresType ashType identityKey generated inversePredicate inverseName storageStrategy sourceKey destinationKey joinTable sourceJoinColumn destinationJoinColumn associationResource enumModule encrypted)`
- Any predicate on an `sh:PropertyShape` within the `r2ml:` namespace that is not a member of `@known_property_terms` triggers an immediate typed refusal (`:REFUSED_SHACL_PROFILE_INCOMPLETE`) carrying `got: terms`.
- Silent omission or ignoring of unconsumed terms is strictly prohibited.

### Invariant 3: VM-Independent Deterministic Action Kind Admission
- Parsing of action kinds (`:create`, `:read`, `:update`, `:destroy`) must never rely on `String.to_existing_atom/1`.
- `AshR2RML.Ingestion.action_kind/2` maps string values to atom literals via explicit pattern matching clauses. Any unexpected value yields `:REFUSED_SHACL_PROFILE_INCOMPLETE`.
- Guarantees cold-VM determinism across fresh BEAM nodes without prior atom table pollution.

### Invariant 4: Discrete Policy Node AND-Composition
- When multiple `r2ml:policy` nodes are attached to a resource shape (e.g. tenant scope check and capability check), each node maps to an independent `policy <action_type> do ... end` block.
- Ash evaluates distinct policy blocks conjunctively (logical AND). Satisfying a capability policy cannot bypass a tenant scoping policy.

### Invariant 5: Ancestry Court Staleness Allowlist & Integration Pin Law
- Documentation and runtime test commit pins must be valid 40-hex SHAs and direct historical ancestors of live HEAD.
- Asynchronous pin updates are permitted only when explicit entries exist in `@staleness_allowlist` with a documented `as_of` date and rationale.
- Integration tests assert that un-allowlisted pins match live HEAD, preventing stale documentation rot.

---

## 4. Verification & Qualification Gates

| Gate | Target Command | Invariant Enforced | Status |
|---|---|---|---|
| **G1** | `mix format --check-formatted` | Code formatting consistency across all modules and tests | PASS (0 errors) |
| **G2** | `mix compile --warnings-as-errors` | Zero compiler warnings; typespec and macro hygiene | PASS (0 warnings) |
| **G3** | `mix test test/encrypted_and_policy_and_test.exs` | Real AshCloak AES-GCM round trip, SQL/Ecto rendering, term refusal, policy AND | PASS (7 tests, 0 failures) |
| **G4** | `mix test test/unit/ggen_runtime_ancestry_test.exs` | Ancestry court with fresh staleness allowlist | PASS (3 tests, 0 failures) |
| **G5** | `mix test test/ontology_first_extensions_test.exs` | Semantic extensions (enums, multitenancy, state machines) | PASS (22 tests, 0 failures) |
| **G6** | `mix hex.build` | Hermetic package build, checksum verification, payload census | PASS (1.36 MB, 0 warnings) |
