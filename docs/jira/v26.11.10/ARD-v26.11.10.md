# ARD v26.11.10 — Architecture Requirements Document

**Title:** Domain Derivation Rules, Inverse Validation Invariants & Packaging Architecture  
**Status:** IMPLEMENTED / ADMITTED  
**Component:** `AshR2RML` Semantic Compiler, SemanticIR, Admission, Renderers, Packaging  
**Scope:** Architecture and structural invariants for milestone v26.11.10  
**Release:** `v26.11.10`  
**Repository:** `seanchatmangpt/ash_r2rml`  
**Authority Ceiling:** `:NONE` (observe-only execution; no DO; no live publication)

---

## 1. Architectural Objective

Preserve the fundamental product invariant of AshR2RML:
> **AshR2RML is the W3C R2RML/RDF semantic-mapping and DfCM type-compiler layer for Ash Framework. It is not an `Ash.DataLayer`, graph database, triplestore, or replacement persistence layer.**

The v26.11.10 architecture introduces first-class Ash 3.0 Domain Module projection and bidirectional relationship synthesis into the ontology-first compilation pipeline, while maintaining strict fail-closed admission rules, cryptographic receipts, and authority boundaries.

---

## 2. Component Architecture & Ingestion Flow

The ontology-first compilation pipeline operates as a deterministic multi-stage transformation:

```text
[Turtle / SHACL Profile]
           │
           ▼
[AshR2RML.Ingestion]  ── parses shapes, `r2ml:domainModule`, `r2ml:inverseName`
           │
           ▼
[AshR2RML.SemanticIR] ── immutable typed IR (`Resource`, `Relationship`, `Attribute`)
           │
           ▼
[AshR2RML.Admission]  ── fail-closed validation (`verify_domain/1`, `verify_inverse_names/1`)
           │
           ▼
[AshR2RML.SemanticRenderers] ── AST / source rendering (`Ash.Domain`, `Ash.Resource`)
           │
           ▼
[AshR2RML.Ggen]       ── file layout dispatch (`:single` vs `:per_resource`) & receipts
```

### Component Roles

| Component | Modules | Responsibility |
|---|---|---|
| Ingestion | `AshR2RML.Ingestion` | Extracts RDF triples, SHACL shapes, custom `r2ml:*` predicates into raw intermediate terms |
| Semantic IR | `AshR2RML.SemanticIR`, `SemanticIR.Resource`, `SemanticIR.Relationship` | Formal typed representation of admitted classes, attributes, relationships, and domains |
| Admission | `AshR2RML.Admission` | Gates invalid inputs with typed `%AshR2RML.Refusal{}` structs |
| Renderers | `AshR2RML.SemanticRenderers`, `AshR2RML.Semantic.Ash` | Emits compilable Elixir code for `Ash.Domain` and `Ash.Resource` modules |
| Bundler & Receipts | `AshR2RML.Ggen` | Partitions code into layout bundles (`:single` vs `:per_resource`) and seals cryptographic receipts |

---

## 3. Core Architectural Invariants

### Invariant 1: Domain Module Admission & Derivation
- When `r2ml:domainModule` is declared on an `sh:NodeShape`, it must satisfy Elixir module name syntax: `~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/`.
- Malformed module identifiers must fail closed at admission with `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.
- All resources declaring the same domain module are grouped under a single synthesized `defmodule <DomainModule> do use Ash.Domain, validate_config_inclusion?: false ... end`.
- Each member resource declares `domain: <DomainModule>` in its `use Ash.Resource` DSL macro.
- If no resources declare a domain, no domain module is generated; resources retain `domain: nil`.

### Invariant 2: Inverse Relationship Synthesis & Collision Safety
- Inverse relationships declared via `r2ml:inverseName` on property shapes generate `has_many <inverse_name>, <SourceModule>` on the target resource.
- **Naming Rule**: Inverse names must be valid snake_case identifiers (`~r/\A[a-z_][a-z0-9_]*\z/`).
- **Collision Invariant**: `AshR2RML.Admission.verify_inverse_names/1` enforces three collision guards:
  1. No collision between an inverse name and any existing attribute on the destination resource.
  2. No collision between an inverse name and any forward relationship on the destination resource.
  3. No collision between multiple inverse relationships targeting the same destination resource with the same name.
- Any collision must fail closed with `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.
- Inverse key mapping is strictly symmetrical:
  ```elixir
  # Forward relationship on Source:
  belongs_to :destination, DestinationModule, source_attribute: :dest_id, destination_attribute: :id

  # Projected inverse relationship on Destination:
  has_many :sources, SourceModule, source_attribute: :id, destination_attribute: :dest_id
  ```

### Invariant 3: Per-Resource Layout & File-Set Receipts
- In `:per_resource` layout, the emitted bundle contains:
  - `generated/ash/<domain_snake>/<resource_snake>.ex` for every entity resource.
  - `generated/ash/<domain_snake>/<join_resource_snake>.ex` for many-to-many join resources.
  - `generated/ash/<domain_snake>.ex` for domain modules.
  - `receipts/ash-file-set.json` sealing the multi-file manifest.
- Each generated file must include a deterministic provenance header:
  `# GENERATED by ash_r2rml — DO NOT EDIT. Source: <shape_iri>`.
- The `receipts/ash-file-set.json` manifest records:
  - `layout`: `"per_resource"`
  - `single_source_ash_sha256`: SHA-256 of the concatenated single-file representation
  - `files`: Map of relative file paths to their individual SHA-256 digests.
- Invalid layout options (e.g. `files: :unsupported`) return `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.

### Invariant 4: Security Disclosure Boundary
- The repository-wide security invariant remains inviolable:
  > **`RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`**
- Postgres/Ontop queries: attributes carrying an explicit `field_policy` are stripped by `AshR2RML.Security.sanitize_mapping/2` before mapping rendering to prevent direct JDBC bypass.
- In-Memory queries: extension-manufactured calculations (`ash_cloak` `decrypt_by_default`) are stripped by `AshR2RML.Security.sanitize_in_memory_mapping/2` prior to RDF graph materialization.
- Virtual Knowledge Graph federation is observe-only; authority is ceilinged at `:NONE`.

### Invariant 5: Additive IR Provenance Slots for Extensions
- Extension terms (enums, multitenancy, actions, policies, state machines, generated flags) reside in existing `provenance` slots of `Resource`, `Relationship`, and `Attribute` (or existing fields like `Action.input_shape`, `Policy.expression`).
- Non-extension profiles retain 100% byte-identical IR representations, graph hashes, and code generation output, maintaining strict backward compatibility and DfCM conservation.

### Invariant 6: Ingestion Determinism & Parser Blank-Node Isolation
- Parsing and compilation is a pure functional transform ($A = \mu(O^*)$) across independent OS processes and runtimes.
- Parser-generated blank-node identifiers (e.g. `_:b0`) are isolated and stripped prior to semantic hashing and IR derivation, preventing non-deterministic digest divergence across execution environments.

### Invariant 7: Policy Check Residue Separation
- Authorization policies declaring `authorize_if <CheckModule>` or `bypass_actor <CheckModule>` require hand-written Elixir policy check modules.
- Hand-written modules are never stubbed, faked, or generated as dummy facades; instead, their requirement is explicitly tracked and sealed in `receipts/ash-residue.json` as irreducible external residue.

---

## 4. Verification & Qualification Gates

| Gate | Target Command | Invariant Enforced |
|---|---|---|
| **Gate 1: Format** | `mix format --check-formatted` | Code formatting consistency across all source and test files |
| **Gate 2: Types & Warnings** | `mix compile --warnings-as-errors` | Zero compiler warnings in `lib/` and clean typespec compilation |
| **Gate 3: Ancestry Court** | `mix test test/unit/ggen_runtime_ancestry_test.exs` | All runtime documentation pins resolve to live HEAD commit SHA |
| **Gate 4: Domain & Inverses** | `mix test test/ontology_first_domains_test.exs` | End-to-end compilation of generated Ash domains, resources, and inverses |
| **Gate 5: Trust Mirror** | `mix test test/unit/castle_bridge_contract_test.exs` | Bilateral symmetry with consumer packs validated |
| **Gate 6: Core Test Suite** | `mix test --exclude external` | 100% test passing rate across unit, negative, and contract suites |
| **Gate 7: Hex Packaging** | `mix hex.build` | Package tarball size <8 MB, valid checksum, zero publish execution |
| **Gate 8: Semantic Extensions** | `mix test test/ontology_first_extensions_test.exs` | Enums, multitenancy, actions, policies, state machines, and residue verification |
| **Gate 9: Ingestion Determinism** | `mix test test/ingestion_determinism_test.exs` | Multi-process statement shuffling and blank-node isolation determinism |

---

## 5. Acceptance Criteria

- [ ] Domain modules derived from `r2ml:domainModule` compile cleanly with `use Ash.Domain`.
- [ ] Inverses derived from `r2ml:inverseName` project working `has_many` associations with inverted keys.
- [ ] Admission rejects malformed domain names and colliding inverse names with `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [ ] `files: :per_resource` generates clean modular directories and valid `receipts/ash-file-set.json`.
- [ ] Semantic extensions compile with full Ash DSL conformance and emit `receipts/ash-residue.json`.
- [ ] Multi-process ingestion tests confirm byte-identical compilation across randomized blank-node labels.
- [ ] All 9 qualification gates pass with exit code 0.
