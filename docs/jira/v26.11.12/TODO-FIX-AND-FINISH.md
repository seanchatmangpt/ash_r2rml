# TODO-FIX-AND-FINISH (ash_r2rml)

Standing: UNVERIFIED

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R8, re-read where marked confirmed.

## Fix

- HIGH `test/unit/ggen_runtime_ancestry_test.exs:30-43` both pins in `@staleness_allowlist`,
  no expiry, `@today` hard-coded "2026-11-10" (confirmed). Check: test fails on a stale pin.
- HIGH `lib/ash_r2rml/ingestion.ex:346` -> `semantic_renderers.ex:460` raw `postgres_type`
  interpolated unquoted into DDL (confirmed). Check: hostile type literal refused.
- MED `ingestion.ex:808-817` `other -> other` fail-open storageStrategy (confirmed).
- MED `ingestion.ex:804` `Module.concat` on `ashType` (confirmed); other atom sites
  (`semantic_renderers.ex`, `telemetry/ocel_v2.ex:234,491`) UNVERIFIED.
- MED `Code.eval_string` over livebooks (`integrity.ex:1325`,
  `mix/tasks/ash_r2rml.test_livebooks.ex:90`, confirmed). Check: allowlisted cells only.
- LOW `Process.sleep` in `concurrency_test.exs`, `dfcm_semantic_execution_integrity_test.exs:279`
  UNVERIFIED (paths moved). Check: `rg 'Process.sleep' test` empty.

## Finish

- Quote/validate `postgres_type` against an allowlist; trace `admission.ex:120-135` UNVERIFIED.
- Bound atom admission via the existing `safe_atom` (`ingestion.ex:821-831`).

## Commit hygiene

`git status --short` (confirmed): modified `CHANGELOG.md`, `ggen.toml`,
`test/unit/ggen_runtime_ancestry_test.exs`; untracked `docs/jira/v26.11.11/`.

## Decide

- Allowlist expiry policy for pin staleness (date source, max age).

## Reuse

- `ingestion.ex:263-285` fail-closed SHACL term allowlist; `semantic_extensions.ex:41-42`.

## See Also

- `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md`
