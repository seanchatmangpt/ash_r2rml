# R2RML-261110-05: Ggen Runtime Pin Refresh & Ancestry Court Enforcement

**Title:** Ggen Runtime Pin Refresh & Ancestry Court Enforcement  
**Ticket Key:** `R2RML-261110-05`  
**Type:** Enhancement / Testing  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** Medium  
**Component:** `AshR2RML.GgenRuntime`, Test Suite, Documentation  
**Scope:**
- `documentation/how_to/ggen_runtime_integration.md`
- `test/unit/ggen_runtime_test.exs`
- `test/unit/ggen_runtime_ancestry_test.exs`

---

## 1. Context

Code examples in documentation and test suites frequently pin specific Git commit SHAs to provide deterministic subject identity. Over time, as new commits land on `dev`, these pins drift. Without automated courts, documentation pins point to ancient commits or detached commits that no longer exist in the repository's lineage.

This enhancement introduces an automated Ancestry Court (`test/unit/ggen_runtime_ancestry_test.exs`) that enforces that every documented runtime pin is a valid, 40-hex commit that exists in the repository and is an ancestor of the live HEAD.

---

## 2. Task Requirements

1. **Commit Pin Refresh**:
   - Refresh pinned commit SHAs in `documentation/how_to/ggen_runtime_integration.md` and `test/unit/ggen_runtime_test.exs` from the stale `37ce7e01` commit to the current live release HEAD: `c395b33a358571d4a` (full SHA `c395b33a358571d4a90c77e2099df2609a816e2f`).
2. **Ancestry Court Implementation (`test/unit/ggen_runtime_ancestry_test.exs`)**:
   - Verify that all `@pin_sites` (`documentation/how_to/ggen_runtime_integration.md` and `test/unit/ggen_runtime_test.exs`) contain non-empty pin lists.
   - Assert that each pin:
     - Is a valid hex SHA with at least 8 characters.
     - Resolves to a full 40-hex commit in the repository via `git rev-parse --verify`.
     - Is an ancestor of HEAD via `git merge-base --is-ancestor`.
   - If a pin is not the current HEAD, require an entry in `@staleness_allowlist` with a valid `as_of` date (`<= @today`). Emit `STALE_PIN_WARNING` for allowlisted pins; fail with `STALE_PIN[site]` for un-allowlisted pins.
   - Assert that the refreshed integration pin matches live HEAD.
3. **Automated Verification**:
   - Ensure `mix test test/unit/ggen_runtime_ancestry_test.exs` passes 100% (3 tests, 0 failures).

---

## 3. Acceptance Criteria

- [ ] All pin occurrences in documentation and test suites resolve to valid commits in the repository.
- [ ] Every pin is verified to be an ancestor of the live repository HEAD.
- [ ] Live HEAD commit is present in the refreshed pin set.
- [ ] Stale pins trigger `STALE_PIN[site]` test failures unless explicitly registered in `@staleness_allowlist`.
- [ ] `mix test test/unit/ggen_runtime_ancestry_test.exs` passes with 0 failures.

---

## 4. Verification Method

Run the ancestry court test suite:

```bash
mix test test/unit/ggen_runtime_ancestry_test.exs
```
