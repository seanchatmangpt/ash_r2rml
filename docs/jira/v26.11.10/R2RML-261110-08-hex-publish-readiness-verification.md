# R2RML-261110-08: Hex Package Build Verification & Release Gate for v26.11.10

**Title:** Hex Package Build Verification & Release Gate for v26.11.10  
**Ticket Key:** `R2RML-261110-08`  
**Type:** Release Gate  
**Status:** VERIFIED / READY  
**Priority:** Highest  
**Component:** Packaging (`mix.exs`, `package/0`, `CHANGELOG.md`)  
**Scope:**
- `mix.exs`
- `CHANGELOG.md`
- Hex package files and build output

---

## 1. Context

AshR2RML is distributed as an open-source hex package (`:ash_r2rml`). Preparing milestone `v26.11.10` for publication requires strict verification of package metadata, version parity across carriers, changelog completeness, tarball size (<8 MB), license compliance, and compilation purity.

Under the operating doctrine, live publication (`mix hex.publish`) is strictly prohibited during qualification runs. Verification is performed strictly via dry-run commands (`mix hex.build`).

---

## 2. Task Requirements

1. **Version Parity**:
   - Align `@version` in `mix.exs:9` to `"26.11.10"`.
   - Ensure `CHANGELOG.md` carries section `## v26.11.10 (2026-11-10)` documenting all features, enhancements, and fixes.
2. **Package Specification Audit (`mix.exs:package/0`)**:
   - Verify all file globs in `package[:files]` resolve to real files on disk:
     - `lib/`, `.formatter.exs`, `mix.exs`, `AGENTS.md`, `usage-rules.md`, `usage-rules/`, `README*`, `LICENSE*`, `CHANGELOG*`, `ash_r2rml.livemd`, `priv/`.
   - Verify `maintainers`, `licenses: ["MIT"]`, and `links` point to valid URLs.
3. **Hex Build Execution**:
   - Run `mix hex.build`.
   - Confirm exit code 0, package size ~1.3 MB, and checksum generation.
   - Verify that unpacked metadata (`hex_metadata.config`) reflects correct version, dependencies, and requirements.
4. **Publish Prohibition Guard**:
   - Do NOT run `mix hex.publish`. Live publication is reserved for automated CI release workflows on signed git tag pushes.

---

## 3. Acceptance Criteria

- [ ] `@version` in `mix.exs` matches `"26.11.10"`.
- [ ] `CHANGELOG.md` begins with `## v26.11.10 (2026-11-10)`.
- [ ] All declared package files exist and contain appropriate license declarations.
- [ ] `mix hex.build` succeeds with exit code 0 and emits no build warnings.
- [ ] The generated tarball size is well within Hex limits (<8 MB, measured ~1.3 MB).
- [ ] Zero live publish commands (`mix hex.publish`) were executed.

---

## 4. Verification Method

Execute package build and inspect output:

```bash
mix hex.build
ls -lh ash_r2rml-26.11.10.tar
tar -tf ash_r2rml-26.11.10.tar
```
