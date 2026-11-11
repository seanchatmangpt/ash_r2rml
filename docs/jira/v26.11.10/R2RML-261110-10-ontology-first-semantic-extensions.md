# R2RML-261110-10: Ontology-First Semantic Extensions (Enums, Tenancy, Actions, Policies, State Machines & Residue)

**Title:** Ontology-First Semantic Extensions (Enums, Tenancy, Actions, Policies, State Machines & Residue)  
**Ticket Key:** `R2RML-261110-10`  
**Type:** Feature  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** High  
**Component:** `AshR2RML.Semantic.Extensions`, `AshR2RML.Ingestion`, `AshR2RML.Admission`, `AshR2RML.SemanticRenderers`, `AshR2RML.Ggen`  
**Scope:**
- `lib/ash_r2rml/semantic_extensions.ex`
- `lib/ash_r2rml/ingestion.ex`
- `lib/ash_r2rml/admission.ex`
- `lib/ash_r2rml/semantic_renderers.ex`
- `lib/ash_r2rml/ggen.ex`
- `test/fixtures/natfac_slice1.profile.ttl`
- `test/ontology_first_extensions_test.exs`

---

## 1. Context

Standard R2RML and basic Ash mapping handle relational tables, scalar datatypes, and foreign-key relationships. However, production-grade Ash systems require rich behavioral constructs:
- Custom enumeration types (`Ash.Type.Enum`) backed by SHACL `sh:in` value sets.
- Attribute-based multitenancy (`multitenancy do strategy :attribute ... end`).
- Primary and custom actions (`create`, `read`, `update`, `destroy`) with typed arguments and accepted attributes.
- Declarative authorization policies (`policies do policy ... authorize_if ... end`).
- Finite state machines (`state_machine do initial ... transitions ... end`).
- Generated primary keys (`r2ml:generated true` for UUIDs).
- Tracking hand-written policy check modules as irreducible residue.

To preserve the DfCM invariant, all additive semantic terms live in existing IR slots (`provenance`, `Action.input_shape`, `Policy.expression`) so that ontologies without these terms retain 100% byte-identical IR, hashes, and emitted code.

---

## 2. Task Requirements

1. **Ingestion (`lib/ash_r2rml/ingestion.ex`)**:
   - Extract `sh:in` lists and optional `r2ml:enumModule` into attribute provenance (`:enum`).
   - Extract `r2ml:multitenancy` (`tenantStrategy`, `tenantAttribute`, `tenantGlobal`) into resource provenance.
   - Extract `r2ml:action` (`actionName`, `actionKind`, `primary`, `accept`, arguments) into resource actions.
   - Extract `r2ml:policy` (`policyName`, `actionType`, `authorizeIf`, `bypassActor`) into resource policies.
   - Extract `r2ml:stateMachine` (`stateAttribute`, `initial`, `terminal`, `transition` list) into resource provenance.
   - Extract `r2ml:generated` boolean flag for identity attributes.
2. **Admission Validation (`lib/ash_r2rml/admission.ex`, `AshR2RML.Semantic.Extensions.verify/1`)**:
   - Validate enum values and ensure that any shared `r2ml:enumModule` carries identical `sh:in` value sets across all referencing shapes.
   - Validate action kinds (`:create`, `:read`, `:update`, `:destroy`) and argument datatypes.
   - Validate that policies reference syntactically valid Elixir module names for `authorize_if` and `bypass_actor`.
   - Validate state machine transitions (initial state exists, actions correspond to declared resource actions).
   - Return typed refusal `{:error, %AshR2RML.Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}}` on any invalid or conflicting specification.
3. **AST & Code Rendering (`lib/ash_r2rml/semantic_renderers.ex`, `AshR2RML.Semantic.Extensions`)**:
   - Emit discrete `defmodule <EnumModule> do use Ash.Type.Enum, values: [...] end` modules.
   - Render `multitenancy do strategy :attribute; attribute :<tenant_attr>; global? <bool> end` on resources.
   - Render `actions do ... end` blocks containing primary actions and custom actions with typed `argument` declarations.
   - Render `policies do policy <action_type> do authorize_if <CheckModule> end end` blocks.
   - Render `state_machine do ... end` blocks with configured initial states, terminal states, and transition rules.
4. **Residue Manifest Generation (`lib/ash_r2rml/ggen.ex`)**:
   - Identify all policy check modules referenced by `authorize_if` and `bypass_actor`.
   - Seal `receipts/ash-residue.json` enumerating all required hand-written check modules with resource and policy bindings.
5. **Automated Verification**:
   - Execute `test/ontology_first_extensions_test.exs` compiling the emitted AST for `natfac_slice1.profile.ttl` and introspecting the resulting Ash domain, resources, enums, multitenancy, and actions.

---

## 3. Acceptance Criteria

- [ ] Profiles with `sh:in` synthesize working `Ash.Type.Enum` modules and bind them to resource attributes.
- [ ] Conflicting `sh:in` values for a shared `r2ml:enumModule` trigger typed refusal `:REFUSED_UNPROVEN_EQUIVALENCE`.
- [ ] Multitenancy definitions compile cleanly with `strategy :attribute`.
- [ ] Actions and arguments compile and execute in Ash changeset/read pipelines.
- [ ] State machines compile and validate valid vs invalid transitions.
- [ ] Generated `receipts/ash-residue.json` correctly enumerates all external check module dependencies.
- [ ] `mix test test/ontology_first_extensions_test.exs` passes 100% with 0 failures.

---

## 4. Verification Method

```bash
mix test test/ontology_first_extensions_test.exs
```
