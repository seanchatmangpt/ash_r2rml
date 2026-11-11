# R2RML-261110-01: Ontology-First Ash Domain Projection (`r2ml:domainModule`)

**Title:** Ontology-First Ash Domain Projection (`r2ml:domainModule`)  
**Ticket Key:** `R2RML-261110-01`  
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

Ash 3.0 establishes `Ash.Domain` as the governing boundary for resources, actions, policies, and authorization contexts. Historically, AshR2RML generated standalone Ash resources with `domain: nil`. When downstream projects ingested SHACL profiles, resources lacked domain grouping, requiring developers to manually hand-write domain modules and register each resource.

This feature enables declarative specification of governing domain modules directly within SHACL profiles via the predicate `r2ml:domainModule`.

---

## 2. Task Requirements

1. **Ingestion (`lib/ash_r2rml/ingestion.ex`)**:
   - Parse `r2ml:domainModule` from `sh:NodeShape` definitions into the raw resource property map:
     ```elixir
     put_optional(:domain, optional_literal(index, shape, @r2ml <> "domainModule"))
     ```
2. **Semantic IR (`lib/ash_r2rml/semantic_ir.ex`)**:
   - Add `:domain` field to `%AshR2RML.SemanticIR.Resource{}` struct and update its typespec.
   - Preserve `:domain` through IR transformation stages.
3. **Admission Gate (`lib/ash_r2rml/admission.ex`)**:
   - Implement `verify_domain/1` to validate that any declared domain string is a syntactically valid Elixir module name:
     ```elixir
     ~r/\A[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/
     ```
   - Return typed refusal `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}` if the module name is malformed.
4. **Code Rendering (`lib/ash_r2rml/semantic_renderers.ex`)**:
   - Group all resources sharing a common domain module.
   - Render a governing `Ash.Domain` module for each unique domain:
     ```elixir
     defmodule <DomainModule> do
       use Ash.Domain, validate_config_inclusion?: false

       resources do
         resource <Resource1>
         resource <Resource2>
       end
     end
     ```
   - Inject `domain: <DomainModule>` into each resource's `use Ash.Resource` DSL declaration.
5. **Fixtures and Automated Tests**:
   - Author SHACL profile fixture `test/fixtures/natfac.profile.ttl` specifying `r2ml:domainModule "NatFac.Facilities"`.
   - Implement test cases in `test/ontology_first_domains_test.exs` compiling the generated domain and verifying resource membership.

---

## 3. Acceptance Criteria

- [ ] `r2ml:domainModule` is successfully extracted from SHACL NodeShape graphs without error when present.
- [ ] Omission of `r2ml:domainModule` defaults `:domain` to `nil` without altering IR hash.
- [ ] Invalid domain module strings (e.g. `"lowercase.domain"`, `"123Invalid"`) fail closed with `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [ ] Generated `Ash.Domain` modules declare `use Ash.Domain, validate_config_inclusion?: false` and correctly list all member resources in `resources do resource ... end`.
- [ ] Member resources declare `use Ash.Resource, domain: <DomainModule>`.
- [ ] Test suite `test/ontology_first_domains_test.exs` executes and passes 100%.

---

## 4. Verification Method

Execute the automated test suite targeting domain projection:

```bash
mix test test/ontology_first_domains_test.exs
```
