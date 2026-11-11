# R2RML-261110-02: Inverse Relationship Synthesis & Collision Admission (`r2ml:inverseName`)

**Title:** Inverse Relationship Synthesis & Collision Admission (`r2ml:inverseName`)  
**Ticket Key:** `R2RML-261110-02`  
**Type:** Feature  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** High  
**Component:** `AshR2RML.Ingestion`, `AshR2RML.SemanticIR`, `AshR2RML.Admission`, `AshR2RML.SemanticRenderers`  
**Scope:**
- `lib/ash_r2rml/ingestion.ex`
- `lib/ash_r2rml/semantic_ir.ex`
- `lib/ash_r2rml/admission.ex`
- `lib/ash_r2rml/semantic_renderers.ex`
- `test/fixtures/natfac.profile.ttl`
- `test/ontology_first_domains_test.exs`

---

## 1. Context

RDF graphs represent domain connections as directed edges (subject -> predicate -> object). For example, a `Client` shape may declare a forward relationship to `Facility`. In Ash applications, bi-directional navigation is required: users querying `Facility` need to navigate back to all associated `clients`.

Historically, AshR2RML only rendered the forward relationship (`belongs_to :facility, Facility`). Developers had to manually define the reciprocal `has_many :clients, Client`.

This feature introduces `r2ml:inverseName` in SHACL property shapes, enabling automatic synthesis of reciprocal `has_many` relationships with fail-closed collision prevention.

---

## 2. Task Requirements

1. **Ingestion (`lib/ash_r2rml/ingestion.ex`)**:
   - Extract `r2ml:inverseName` literal from property shape definitions:
     ```elixir
     put_optional(:inverse_name, optional_literal(index, property_shape, @r2ml <> "inverseName"))
     ```
2. **Semantic IR (`lib/ash_r2rml/semantic_ir.ex`)**:
   - Add `:inverse_name` field to `%AshR2RML.SemanticIR.Relationship{}` struct and typespec.
3. **Collision-Proof Admission Gate (`lib/ash_r2rml/admission.ex`)**:
   - Implement `verify_inverse_names/1` validating all declared inverse names:
     - Enforce valid snake_case atom names: `~r/\A[a-z_][a-z0-9_]*\z/`.
     - Check for collisions against existing attributes on the destination resource.
     - Check for collisions against forward relationships already declared on the destination resource.
     - Check for collisions between multiple inverse declarations targeting the same destination resource with the same inverse name.
     - Refuse any detected collision with typed refusal `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.
4. **Code Rendering (`lib/ash_r2rml/semantic_renderers.ex`)**:
   - For each relationship declaring `:inverse_name`, render a `has_many` association on the target resource:
     ```elixir
     has_many :<inverse_name>, <SourceResourceModule> do
       source_attribute :<destination_attribute>
       destination_attribute :<source_attribute>
     end
     ```
   - Invert key bindings so the target's primary key aligns with the foreign key on the source resource.
5. **Automated Testing**:
   - In `test/ontology_first_domains_test.exs`, verify that:
     - Valid inverse relationships compile and function in Ash queries.
     - Inverses colliding with existing attributes trigger typed refusal.
     - Duplicate inverse names targeting the same resource trigger typed refusal.

---

## 3. Acceptance Criteria

- [ ] `r2ml:inverseName` is successfully ingested into `%AshR2RML.SemanticIR.Relationship{}`.
- [ ] Inverse names conforming to snake_case format project as valid `has_many` associations.
- [ ] Key mappings on synthesized inverses invert `source_attribute` and `destination_attribute` accurately.
- [ ] Attempting to project an inverse name that matches an existing attribute on the destination resource returns `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.
- [ ] Attempting to project an inverse name that matches an existing forward relationship returns `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.
- [ ] Declaring identical inverse names from two distinct sources targeting the same destination returns `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}`.
- [ ] All tests in `test/ontology_first_domains_test.exs` pass 100%.

---

## 4. Verification Method

Run the domain and inverse relationship test suite:

```bash
mix test test/ontology_first_domains_test.exs
```
