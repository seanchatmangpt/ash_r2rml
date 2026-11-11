# R2RML-261110-09: Five-Persona Architectural & Release Quality Audit Specifications

**Title:** Five-Persona Architectural & Release Quality Audit Specifications  
**Ticket Key:** `R2RML-261110-09`  
**Type:** Audit / Review Protocol  
**Status:** ACTIVE / SPECIFIED  
**Priority:** High  
**Component:** Quality Assurance, Review Framework, Multi-Persona Governance  
**Scope:** Entire repository and release artifacts for milestone v26.11.10  

---

## 1. Context

To ensure the highest standard of architectural integrity, idiomatic correctness, runtime stability, and security before cutting release `v26.11.10`, five specialized expert personas are launched to review the codebase independently:
1. **Zach Daniel**: Ash Framework creator — validates Spark DSL composition, Ash 3.0 domain governance, type system idioms, and data layer separation.
2. **Joe Armstrong**: Erlang co-inventor — evaluates OTP concurrency, process boundaries, fail-fast mechanics, GenServer isolation, and timeout guarantees.
3. **José Valim**: Elixir creator — reviews functional purity, pattern matching, typespec fidelity, error tuple conventions, macro hygiene, and `mix.exs` architecture.
4. **Verification Specialist**: Senior QA / Test Architect — assesses test matrix completeness, adversarial/property tests, determinism, clean-room replay, and refusal code coverage.
5. **Security Auditor**: AppSec specialist — enforces the `RDF disclosure ⊆ Ash disclosure` invariant, field-policy stripping, in-memory calculation exclusions, authority ceilings (`:NONE`), and dependency audit status.

---

## 2. Task Requirements

1. **Deploy Five Review Agents**:
   - Provide each agent with perspective-specific mandates, key files to inspect, probing architectural questions, and explicit sign-off criteria.
2. **Author Five Independent Evaluation Reports**:
   - Each persona must produce a dedicated evaluation report with findings, scorecards, and an explicit recommendation: `APPROVED`, `APPROVED_WITH_CAVEATS`, or `REJECTED`.
3. **Audit Target Matrix**:

| Persona | Primary Focus Area | Key Code Inspection Targets |
|---|---|---|
| **Zach Daniel** | Ash & Spark Architecture | `lib/ash_r2rml.ex`, `lib/ash_r2rml/resource.ex`, `lib/ash_r2rml/introspection.ex`, `lib/ash_r2rml/semantic_renderers.ex` |
| **Joe Armstrong** | OTP & Concurrency | `lib/ash_r2rml/obda.ex` (`run_bounded/4`), `lib/ash_r2rml/telemetry/fly_client.ex`, `mix.exs` (supervision) |
| **José Valim** | Elixir Idioms & Design | `mix.exs`, `lib/ash_r2rml/compiler.ex`, `lib/ash_r2rml/admission.ex`, `lib/ash_r2rml/telemetry/ocel_v2.ex` |
| **Verification Specialist** | Test Rigor & Determinism | `test/unit/ggen_runtime_ancestry_test.exs`, `test/negative/`, `test/fortune5/`, `test/vkg/`, `test/ontology_first_domains_test.exs` |
| **Security Auditor** | Disclosure & Authority | `lib/ash_r2rml/security.ex`, `lib/ash_r2rml/obda_in_memory.ex`, `lib/ash_r2rml/vkg/contract.ex`, `lib/ash_r2rml/knowledge_hooks.ex` |

---

## 3. Detailed Review Rubrics & Criteria

### 3.1 Persona 1: Zach Daniel (Ash Framework Architecture)
- **Mandate**: Ensure AshR2RML acts as a clean Spark extension and type-compiler, never mimicking an `Ash.DataLayer`.
- **Probing Questions**:
  1. Do transformers in `AshR2RML.Resource.Persist` order themselves strictly after Ash primary key and relationship transformers?
  2. Does the ontology-first renderer generate idiomatic Ash 3.0 domain declarations (`use Ash.Domain`)?
  3. Are Ash read options (`actor:`, `tenant:`, `domain:`) preserved through `AshR2RML.OBDA.InMemory` to execute caller policies?
- **Sign-Off Requirements**:
  - [ ] Zero implementation of `Ash.DataLayer` behaviour in `lib/`.
  - [ ] Spark extension loads cleanly without compilation warnings.
  - [ ] Generated resources declare `domain: <DomainModule>` conforming to Ash 3.0 conventions.
  - [ ] `test/zach_features_test.exs` and `test/ontology_first_domains_test.exs` pass 100%.

### 3.2 Persona 2: Joe Armstrong (OTP Principles & Concurrency)
- **Mandate**: Ensure pure compilation logic is stateless and process-free, while external side-effects are failure-isolated and bounded.
- **Probing Questions**:
  1. Does `Ontop.run_bounded/4` use `spawn_monitor` with explicit timeouts and clean exit flushing to prevent zombie processes?
  2. Is `FlyClient` the sole supervised GenServer, and does it feature bounded queues and offline persistence fallbacks?
- **Sign-Off Requirements**:
  - [ ] 100% of compilation and mapping IR logic is pure, stateless functional transformation.
  - [ ] Monitored worker processes in `Ontop.run_bounded/4` do not leak monitors or unhandled `:DOWN` messages.
  - [ ] No raw unmonitored `spawn` calls exist in `lib/`.

### 3.3 Persona 3: José Valim (Elixir Design & Idioms)
- **Mandate**: Enforce idiomatic Elixir patterns, typespec accuracy, clean macro expansions, and standard error tuples.
- **Probing Questions**:
  1. Are error paths uniformly structured as `{:ok, term} | {:error, %AshR2RML.Refusal{}}`?
  2. Are struct literals in `@spec` signatures (e.g. `%Log{}` in `ocel_v2.ex`) properly typed?
  3. Does `mix compile --warnings-as-errors` exit 0?
- **Sign-Off Requirements**:
  - [ ] `mix compile --warnings-as-errors` exits 0.
  - [ ] `mix format --check-formatted` exits 0.
  - [ ] `mix.exs` package metadata specifies correct version, licenses, description, and dependency constraints.

### 3.4 Persona 4: Verification Specialist (Testing Rigor & Coverage)
- **Mandate**: Verify that test suites adhere to the Chicago school (real collaborators over artificial mocks), cover all typed refusal codes, and execute deterministically.
- **Probing Questions**:
  1. Does `test/unit/ggen_runtime_ancestry_test.exs` pass 100% against live HEAD?
  2. Are all 37 typed refusal codes in `AshR2RML.Refusal.code()` exercised by negative tests?
  3. Do replay and VKG tests verify byte-identical hash determinism?
- **Sign-Off Requirements**:
  - [ ] Ancestry court passes with 0 failures (`mix test test/unit/ggen_runtime_ancestry_test.exs`).
  - [ ] Core test suite (`mix test --exclude external`) passes with 0 failures.
  - [ ] Replay tests pass cleanly in clean-room environments.

### 3.5 Persona 5: Security Auditor (RDF Disclosure & Authority Boundaries)
- **Mandate**: Validate the core security law: **`RDF disclosure ⊆ explicitly admitted Ash attribute disclosure`**.
- **Probing Questions**:
  1. Does `AshR2RML.Security.sanitize_mapping/2` strip policied attributes before JDBC execution on Postgres?
  2. Does `AshR2RML.Security.sanitize_in_memory_mapping/2` purge decrypted calculations (`ash_cloak`) before in-memory RDF materialization?
  3. Is the Virtual Knowledge Graph authority ceiling strictly enforced at `:NONE`?
- **Sign-Off Requirements**:
  - [ ] Tests in `test/security_ash_postgres_test.exs` and `test/obda_in_memory_cloak_test.exs` pass 100%.
  - [ ] Any attempt to escalate VKG authority returns `{:error, %Refusal{code: :REFUSED_VKG_AUTHORITY_ESCALATION}}`.
  - [ ] Sobelow security scan passes without high/medium findings.

---

## 4. Acceptance Criteria

- [ ] Detailed review specifications and probing questions published for all 5 personas.
- [ ] 5 independent persona review agents deployed with clear mandates.
- [ ] Explicit sign-off recommendations (`APPROVED`, `APPROVED_WITH_CAVEATS`, or `REJECTED`) documented per persona.
