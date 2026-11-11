# R2RML-261110-06: Doc-Hdit Reference Skeletons & Diataxis Documentation Remediation

**Title:** Doc-Hdit Reference Skeletons & Diataxis Documentation Remediation  
**Ticket Key:** `R2RML-261110-06`  
**Type:** Documentation  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** Medium  
**Component:** Documentation (`documentation/reference/generated/`, `documentation/`)  
**Scope:**
- `documentation/reference/generated/`
- `documentation/reference/dsl_cheatsheet.md`
- `managing_schema.livemd`
- `ash_r2rml.livemd`
- `test/livebook_semantic_integrity_test.exs`

---

## 1. Context

Documentation in prior releases suffered from two critical gaps:
1. **Low Reference Coverage**: Reference documentation covered only 5.3% of the codebase, leaving 230+ modules undocumented.
2. **Disorganized Structure**: Documentation lacked Diataxis structure, mixing tutorials, reference, and how-tos unpredictably. Furthermore, Livebook guides referenced outdated APIs (`AshR2RML.verify/1` instead of `AshR2RML.Resource.Info.mapping_result/1`) and pre-26.10 version pins.

This ticket tracks the doc-hdit remediation program: generating complete reference skeletons under Diataxis principles, achieving 100% module coverage, and synchronizing interactive Livebook guides.

---

## 2. Task Requirements

1. **Diataxis Reference Generation (`documentation/reference/generated/`)**:
   - Generate per-namespace reference documentation covering all 245 modules in `lib/` (883 function and macro definitions across 64 namespace groups).
   - Increase module reference coverage from 5.3% to 100%.
   - Format identifier signatures with backticked headers for consistent HTML/Markdown anchor rendering.
2. **DSL Cheatsheet Cleanup**:
   - Correct heading anchors and syntax examples in `documentation/reference/dsl_cheatsheet.md`.
3. **Livebook Guide Synchronization**:
   - In `managing_schema.livemd`: replace nonexistent `AshR2RML.verify/1` with `AshR2RML.Resource.Info.mapping_result/1`.
   - In `ash_r2rml.livemd` and `managing_schema.livemd`: update dependency install pins to `~> 26.11`.
   - Clean dead relative links across guides.
4. **Automated Verification**:
   - Execute `test/livebook_semantic_integrity_test.exs` to verify Livebook notebook syntax and semantic integrity.

---

## 3. Acceptance Criteria

- [ ] `documentation/reference/generated/` contains reference skeletons covering 100% of `lib/` modules (245/245).
- [ ] Markdown identifiers in generated reference files render with proper backticks and anchors.
- [ ] Livebooks (`managing_schema.livemd`, `ash_r2rml.livemd`) install `~> 26.11` and reference valid APIs.
- [ ] `mix test test/livebook_semantic_integrity_test.exs` passes with 0 failures.

---

## 4. Verification Method

Run the Livebook semantic integrity test suite:

```bash
mix test test/livebook_semantic_integrity_test.exs
```
