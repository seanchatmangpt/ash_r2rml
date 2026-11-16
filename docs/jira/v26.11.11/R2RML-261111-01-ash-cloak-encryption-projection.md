# R2RML-261111-01: AshCloak Semantic Encryption Projection (`r2ml:encrypted`, `r2ml:cloakVault`)

**Title:** AshCloak Semantic Encryption Projection (`r2ml:encrypted`, `r2ml:cloakVault`)  
**Ticket Key:** `R2RML-261111-01`  
**Type:** Feature  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** Highest  
**Component:** `AshR2RML.Ingestion`, `AshR2RML.Semantic.Extensions`, `AshR2RML.Compiler`, `AshR2RML.SemanticRenderers`, `AshR2RML.Semantic.Ecto`, `AshR2RML.Semantic.SQL`  
**Scope:**
- `lib/ash_r2rml/ingestion.ex`
- `lib/ash_r2rml/admission.ex`
- `lib/ash_r2rml/semantic_extensions.ex`
- `lib/ash_r2rml/semantic_renderers.ex`
- `lib/ash_r2rml/compiler.ex`
- `lib/ash_r2rml/ecto.ex`
- `test/encrypted_and_policy_and_test.exs`

---

## 1. Context

Downstream systems handling personally identifiable information (PII), confidential tokens, or sensitive enterprise payloads require at-rest cryptographic encryption. To preserve the repository's foundational security invariant (`RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`), attributes flagged as encrypted must be managed through `AshCloak`, persisted as ciphertext columns in relational databases, and strictly excluded from R2RML RDF mapping projections so that SPARQL or triplestore queries can never expose sensitive data.

---

## 2. Task Requirements

1. **Ingestion (`lib/ash_r2rml/ingestion.ex`)**:
   - Extract `r2ml:cloakVault` string/IRI literal from `sh:NodeShape` into `resource.provenance[:cloak_vault]`.
   - Extract `r2ml:encrypted true` boolean literal from `sh:PropertyShape` into `attribute.provenance[:encrypted]`.
2. **Admission Invariants (`lib/ash_r2rml/semantic_extensions.ex`, `admission.ex`)**:
   - In `Extensions.verify_encrypted/1`:
     - Assert that any resource containing an encrypted attribute has a valid `cloak_vault` defined. Fail closed with typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE` ("r2ml:encrypted requires r2ml:cloakVault on the resource shape") if missing.
     - Assert that an encrypted attribute is not flagged as an identity key (`attribute.provenance[:identity_key] != true`). Fail closed with `:REFUSED_UNPROVEN_EQUIVALENCE` ("r2ml:encrypted attribute cannot be an identity key") if violated.
3. **Resource Code Generation (`lib/ash_r2rml/semantic_renderers.ex`, `semantic_extensions.ex`)**:
   - Inject `extensions: [AshCloak]` into the resource `use Ash.Resource` header when encrypted attributes exist.
   - Render DSL block via `Extensions.render_cloak/1`:
     ```elixir
     cloak do
       vault <VaultModule>
       attributes [:<attr1>, :<attr2>]
     end
     ```
   - In attribute definitions, emit `public?: false` when `Extensions.encrypted?(attribute)` is true (non-encrypted attributes default to `public?: true`).
   - In default actions (`create`, `update`), append `default_accept [:<encrypted_attr>, ...]` to allow caller changesets to write plaintext data into private fields.
4. **Relational Schema Projection (`lib/ash_r2rml/semantic_renderers.ex`, `ecto.ex`)**:
   - In SQL DDL (`AshR2RML.Semantic.SQL.column_definition/1`), emit `"encrypted_<attr>" bytea<nullability>` instead of standard type.
   - In Ecto migrations (`AshR2RML.Semantic.Ecto.render_attribute/1`), emit `add :"encrypted_<attr>", :binary, null: <bool>, primary_key: false`.
5. **R2RML RDF Disclosure Defense (`lib/ash_r2rml/compiler.ex`, `semantic_renderers.ex`)**:
   - In `AshR2RML.SemanticAdapter.convert_resource/2` and `AshR2RML.Semantic.R2RML.render_resource/2`, filter out encrypted attributes:
     `Enum.reject(&AshR2RML.Semantic.Extensions.encrypted?/1)`.
   - Guaranteed: neither plaintext nor ciphertext is projected into `PredicateObjectMaps` or virtual graphs.
6. **Integration Verification (`test/encrypted_and_policy_and_test.exs`)**:
   - Author end-to-end tests setting up a real `Cloak.Vault` with AES-GCM 256-bit encryption.
   - Verify that record creation encrypts plaintext at rest in ETS/storage, and read queries return decrypted values only through Ash actions.

---

## 3. Acceptance Criteria

- [x] SHACL Turtle profiles declaring `r2ml:encrypted true` and `r2ml:cloakVault` ingest without errors.
- [x] Encrypted attributes missing `r2ml:cloakVault` trigger typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [x] Encrypted attributes marked `r2ml:identityKey true` trigger typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [x] Generated Ash resources include `AshCloak` extension and formatted `cloak do ... end` block.
- [x] Plaintext attributes are generated with `public?: false` and included in default action `default_accept`.
- [x] SQL DDL emits `encrypted_<attr>` as `bytea` and Ecto migration emits `add :"encrypted_<attr>", :binary`.
- [x] R2RML compiler rejects encrypted attributes from predicate object maps.
- [x] Real Cloak vault round trip encrypts plaintext and allows transparent reading via Ash.
- [x] All 7 tests in `test/encrypted_and_policy_and_test.exs` pass with 0 failures.

---

## 4. Verification Method

```bash
# Execute the AshCloak encryption test suite
mix test test/encrypted_and_policy_and_test.exs

# Expected output:
# Finished in ~7 seconds
# 7 tests, 0 failures
```
