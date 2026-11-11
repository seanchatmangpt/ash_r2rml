# R2RML-261110-07: Release Workflow Retirement & Version Carrier Alignment

**Title:** Release Workflow Retirement & Version Carrier Alignment  
**Ticket Key:** `R2RML-261110-07`  
**Type:** Chore / Hygiene  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** Medium  
**Component:** CI/CD (`.github/workflows/`), Configuration (`ggen.toml`, `mix.exs`)  
**Scope:**
- `.github/workflows/release-v26.9.28.yml` (retired/deleted)
- `.github/workflows/release.yaml`
- `.github/workflows/exact-head-release-court.yml`
- `ggen.toml`
- `mix.exs`
- `README.md`

---

## 1. Context

During earlier milestone releases, specialized GitHub Actions workflows (such as `.github/workflows/release-v26.9.28.yml`) were introduced to publish specific frozen subjects. If left active, scheduled cron workflows attempt repeated publications against superseded tags, creating noisy failures and potential release collisions.

Additionally, secondary version carriers such as `ggen.toml` must remain synchronized with `mix.exs` to ensure that Ggen manufacturing pipelines report the true project release version.

---

## 2. Task Requirements

1. **Workflow Retirement**:
   - Confirm deletion of `.github/workflows/release-v26.9.28.yml`.
   - Ensure the canonical release workflows remain operative:
     - `.github/workflows/release.yaml`: Tag-driven release publication triggered by `v*` tags.
     - `.github/workflows/exact-head-release-court.yml`: Release court verifying formatting, compilation, test suite, and hex packaging.
2. **Version Carrier Synchronization**:
   - Bump `version` in `ggen.toml` to `"26.11.10"`.
   - Bump `@version` in `mix.exs` to `"26.11.10"`.
3. **Documentation Sync Mechanics**:
   - Correct ontology synchronization claims in `README.md` to reflect real local generation rather than automated push hooks.

---

## 3. Acceptance Criteria

- [ ] `.github/workflows/release-v26.9.28.yml` is absent from the repository.
- [ ] Active release workflows (`release.yaml`, `exact-head-release-court.yml`) are intact.
- [ ] `ggen.toml` specifies `version = "26.11.10"`.
- [ ] `mix.exs` specifies `@version "26.11.10"`.
- [ ] `git diff --exit-code -- mix.lock` passes cleanly with zero unstaged dependency modifications.

---

## 4. Verification Method

Inspect workflow files and version carrier definitions:

```bash
ls -la .github/workflows/
grep "version" ggen.toml
grep "@version" mix.exs
```
