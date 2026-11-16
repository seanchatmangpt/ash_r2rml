# R2RML-261111-02: Property Shape Unknown Terms Refusal Gate

**Title:** Property Shape Unknown Terms Refusal Gate  
**Ticket Key:** `R2RML-261111-02`  
**Type:** Integrity / Refusal  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** High  
**Component:** `AshR2RML.Ingestion`, `AshR2RML.Refusal`  
**Scope:**
- `lib/ash_r2rml/ingestion.ex`
- `test/encrypted_and_policy_and_test.exs`

---

## 1. Context

In ontology-first compiler architectures, silent degradation is a catastrophic failure mode. If a developer or upstream generator misconfigures or misspells a critical security attribute on an `sh:PropertyShape` (for example, typing `r2ml:encrpyted true` instead of `r2ml:encrypted true`), a permissive parser that ignores unconsumed terms would silently generate an unencrypted, public database column. To guarantee fail-closed security, any predicate in the `r2ml:` namespace attached to a property shape that is not explicitly consumed by the compiler must trigger an immediate typed refusal.

---

## 2. Task Requirements

1. **Allowlist Definition (`lib/ash_r2rml/ingestion.ex`)**:
   - Maintain a canonical, comprehensive list of recognized property shape predicates under `@known_property_terms`:
     ```elixir
     @known_property_terms ~w(ashName columnName postgresType ashType identityKey generated
       inversePredicate inverseName storageStrategy sourceKey destinationKey joinTable
       sourceJoinColumn destinationJoinColumn associationResource enumModule encrypted)
     ```
2. **Predicate Filtering (`lib/ash_r2rml/ingestion.ex`)**:
   - Implement `unknown_property_terms/2` to query all predicates for a given property shape in the graph index:
     - Filter for predicates prefixed with `@r2ml` (`https://ash-r2rml.dev/ontology/r2ml#`).
     - Strip the `@r2ml` prefix.
     - Reject terms present in `@known_property_terms`.
     - Return sorted list of unknown terms.
3. **Refusal Gate Enforcement (`lib/ash_r2rml/ingestion.ex`)**:
   - Wire `reject_unknown_terms/2` into `parse_attribute/3`.
   - If unknown terms list is non-empty, halt ingestion immediately:
     ```elixir
     incomplete(subject, "property shape carries unsupported r2ml: terms", %{terms: terms})
     ```
   - Emits typed refusal with code `:REFUSED_SHACL_PROFILE_INCOMPLETE`.
4. **Adversarial Verification (`test/encrypted_and_policy_and_test.exs`)**:
   - Verify that injecting unsupported terms (e.g., `r2ml:bogusProp "val"` or `r2ml:encrpyted true`) triggers `{:error, %AshR2RML.Refusal{code: :REFUSED_SHACL_PROFILE_INCOMPLETE}}` containing the offending predicate.

---

## 3. Acceptance Criteria

- [x] `@known_property_terms` explicitly declares all valid `r2ml:` property shape predicates.
- [x] Any unrecognized `r2ml:*` predicate on an `sh:PropertyShape` triggers an immediate compile-time failure.
- [x] The refusal structure is typed as `%AshR2RML.Refusal{code: :REFUSED_SHACL_PROFILE_INCOMPLETE}`.
- [x] The refusal details map contains the exact list of unsupported terms under `terms: [...]`.
- [x] Adversarial unit tests prove typos (e.g. `r2ml:encrpyted`) fail closed and prevent compilation.

---

## 4. Verification Method

```bash
# Execute the term refusal tests within the encryption suite
mix test test/encrypted_and_policy_and_test.exs

# Direct assertion verified:
# assert {:error, %AshR2RML.Refusal{code: :REFUSED_SHACL_PROFILE_INCOMPLETE, details: %{terms: ["bogusProp"]}}}
```
