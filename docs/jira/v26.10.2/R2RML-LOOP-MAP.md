# R2RML Loop Map — MAP-THEN-CLOSE lane E5 (v26.10.2)

Lane: E5, 2026-10-02. Read-only map + evidence lane; the only files written are this doc.
Repo: `/Users/sac/ash_r2rml` (origin https://github.com/seanchatmangpt/ash_r2rml).

## Subject identity

| fact | value |
|---|---|
| local HEAD | `05e19f8` "fix(sa2a): add bodiless from_source/2 head for defaults" (2026-09-29) |
| origin/main | `36f25a3` "Merge QME-1 canonical hardening rebind" — local HEAD is a strict ancestor, 7 commits behind |
| mix.exs `@version` | `26.9.28` (identical on local HEAD and origin/main) |
| latest tag | `v26.9.28` |
| CHANGELOG head | local **uncommitted** `v26.9.29` entry (SA2AEvidence); origin/main CHANGELOG head is `v26.9.28` |
| hex published | `26.9.28` (2026-09-29) latest (`mix hex.info ash_r2rml`) |
| toolchain pin | `.tool-versions`: elixir `1.18.4-otp-27`, erlang `27.2.4`; local shell default is Elixir `1.19.5` (Homebrew) — see test evidence |

## The map

- **What it is**: W3C R2RML / RDF semantic-mapping compiler for Ash (`mix.exs:11` description). Ash resource + semantic mapping -> `AshR2RML.Mapping` -> R2RML projection over PostgreSQL; also DfCM type-compiler layer. Not a graph DB, not an `Ash.DataLayer`, not a SPARQL engine (`README.md`, `AGENTS.md` product invariant).
- **Version**: `@version "26.9.28"` at `mix.exs:9`; elixir `~> 1.17` at `mix.exs:18`; `.tool-versions` pins elixir `1.18.4-otp-27` / erlang `27.2.4`.
- **lib/ census**: 244 `defmodule` declarations under `lib/`. Top-level surface: `AshR2RML` (facade, `lib/ash_r2rml.ex`), `Compiler`, `Mapping`, `R2RML` renderers (`lib/ash_r2rml/renderers.ex:5`), `SemanticIR`, `Semantic.Ecto`, `OBDA` (+ `OBDA.InMemory`), `VKG` (23 modules, `lib/ash_r2rml/vkg/`), `Federation`, `Security`, `DfCM`, `Reactor`, `Ggen`, `KnowledgeHooks`, `SemanticGraphQL`, `Provenance`, `Telemetry`, `Production`.
- **Refusal taxonomy**: `AshR2RML.Refusal` at `lib/ash_r2rml/mapping.ex:5` — `defstruct [:code, :subject, :detail, evidence: %{}]`, `@enforce_keys [:code, :subject, :detail]`, 43-code `@type code` (26 `REFUSED_*` base + 13 `REFUSED_VKG_*` + `REFUSED_OBDA_EXECUTION` + `REFUSED_RESOURCE_BOUND` + 2 `UNSUPPORTED_*`); 73 total `REFUSED_/UNSUPPORTED_` occurrences in that file including helper heads.
- **Docs**: no `docs/status.md`. `docs/jira/<milestone>/` convention exists (`docs/jira/v26.9.28/` holds VKG-001 PRD/ARD); this doc follows it. `docs/qme-1-reference.md` exists on origin/main only.
- **CI**: 11 workflows in `.github/workflows/` — `ci.yaml` (5 gates: types / release-security / production / test / obda; PR head SHA checkout; no deps/_build caching), `exact-head-release-court.yml`, `release-v26.9.28.yml` + `release.yaml`, `reuse.yaml`, plus 6 specialist courts.
- **Tests**: 261 `*_test.exs` files under `test/`. Two livebook/crown files (`test/integration/obda_crown.exs`, `ontop_compliance_crown.exs`) are flagged by a `test_load_filters` warning — they do not match the default test pattern.

## Test evidence (this lane, 2026-10-02)

1. `MIX_BUILD_ROOT=_build-e5 mix test` (Elixir 1.19.5): suite **aborts** — `SyntaxError` at `test/semantic_ecto_storage_type_test.exs:27:23` ("keyword argument must be followed by space after: ontology:"), 21 tests had run before the abort. Reproduced twice.
2. Root cause located: line 26 uses `~s(...)` whose payload contains a `)` inside `:"geometry(Point,26918)"` — the sigil terminates at that inner paren and garbles the following lines.
3. **origin/main already fixes this exact file** (`git diff HEAD origin/main` rewrites lines ~22-26 to a `~s|...|` sigil). The local checkout is 7 commits behind and carries no local modification to the file (`git status` clean for it) — the breakage is inherited, not lane-introduced.
4. Pinned-toolchain run (elixir 1.18.4-otp-27 via asdf path prepend, erlang 27.2.4): same abort, same file. Not a toolchain-version artifact.
5. Count run (this lane): full suite **excluding that one file**, pinned toolchain, `MIX_BUILD_ROOT=_build-e5` — **992 tests, 0 failures, 9 skipped** (Finished in 12.2s; Elixir 1.18.4 / OTP 27 confirmed in run header). The excluded file is the only blocker between this and a clean full-suite pass at local HEAD; at origin/main (`36f25a3`) the fix is already landed.

## Edge audit

| # | edge | claim | verified state | verdict |
|---|---|---|---|---|
| 1 | ash_a2a -> ash_r2rml | hex dep `{:ash_r2rml, "~> 26.8"}` | `mix.exs:277` confirmed; `mix.lock:8` resolves **hex 26.9.12** (2026-09-13) while hex latest is 26.9.28 — constraint satisfied (`~> 26.8` allows 26.9.x) but lock is 16 patch releases stale. Usage is soft/guarded: `semantic_projection.ex:68` checks `function_exported?(AshR2RML, :mapping_result, 1)` before invoking; `mapping_result/1` exists at `lib/ash_r2rml.ex:78` (defdelegate to `AshR2RML.Resource.Info`). | ALIVE, stale lock (S fix) |
| 2 | xaas -> ash_r2rml (Refusal ride-along) | xaas classifies `AshR2RML.Refusal` as `:semantic_refusal` | `xaas/lib/xaas/fabric/failure.ex:48` `defp classify(%{__struct__: AshR2RML.Refusal}), do: :semantic_refusal` — struct shape unchanged at `lib/ash_r2rml/mapping.ex:5-10`, so the classification holds. xaas consumes Refusal in 7+ modules (`semantics/r2rml.ex:30`, `semantics/vkg*.ex`). xaas pins **git ref `36f25a3`** = current origin/main (`xaas/mix.exs:107-110`, `xaas/mix.lock:26`) — includes SA2AEvidence and the QME hardening; local checkout is what lags, not the pin. | ALIVE, pin current |
| 3 | ggen-marketplace packs | `ash-r2rml-paas-pack` + `ash-r2rml-reactor-paas-pack` | Both exist at `ggen-marketplace/packs/`. Versions: paas-pack `26.8.27`, reactor-paas-pack `26.8.26` (pack.toml); in-repo `ggen.toml` also says `26.8.26` — all vs repo `26.9.28`. Divergence is version-label staleness, not structural: pack-referenced surface (`AshR2RML.Resource`, `AshR2RML.R2RML.render` at `renderers.ex:33/42/46`, `AshR2RML.Compiler.sha256` at `compiler.ex:490`) all still exist. | ALIVE, version-stale (M fix) |

## CI (hosted)

`gh run list -R seanchatmangpt/ash_r2rml -L 3` — three consecutive **success** runs of "v26.9.28 Hex release" on `main` (schedule; most recent 2026-10-03T00:22Z, 14m50s). CI green on origin/main.

## Version/tag/changelog state (report-only; coordinator actions)

- 8 commits since tag `v26.9.28` (incl. `bdd82b2` SA2AEvidence feature + 7 QME hardening commits) carry **no version bump**: `@version` is `26.9.28` on origin/main, CHANGELOG on origin/main has no post-26.9.28 entry.
- The `v26.9.29` CHANGELOG entry + `usage-rules/vkg.md` SA2A section exist **only as uncommitted local edits** in this checkout.
- Scheduled "v26.9.28 Hex release" keeps re-publishing the old subject on a timer.
- Tag decision (`tag if CHANGELOG == mix.exs == released`): not satisfied — CHANGELOG(working tree) is `v26.9.29` while `mix.exs` says `26.9.28` and no `v26.9.29` tag exists. Do NOT tag `v26.9.29` until `@version` is bumped and the changelog commits.

## Loop-closure backlog (ranked; cost S/M/L)

| rank | loop | closure action | cost |
|---|---|---|---|
| 1 | local checkout 7 commits behind origin/main, and HEAD's `test/semantic_ecto_storage_type_test.exs` carries a suite-aborting SyntaxError already fixed upstream | coordinator fast-forwards local `main` to `36f25a3` (commit the two pending local doc edits first or rebase them on top); local suite abort disappears | S |
| 2 | version drift: 8 feature-bearing commits since tag with `@version`/CHANGELOG/tag stuck at 26.9.28 | bump `@version` to `26.9.29`, commit the existing CHANGELOG + usage-rules entries, tag `v26.9.29`, let the release workflow publish | S |
| 3 | ash_a2a lock stale at hex 26.9.12 (latest 26.9.28) | in ash_a2a: `mix deps.update ash_r2rml`, run its suite, land lock bump | S-M |
| 4 | marketplace packs (26.8.26/26.8.27) and in-repo `ggen.toml` (26.8.26) version-stale vs repo 26.9.28; pack qualification last touched at v26.9.28 consolidation | re-qualify both packs against ash_r2rml 26.9.28/26.9.29 surface, bump pack.toml versions, re-run qualification harness | M |
| 5 | scheduled "v26.9.28 Hex release" workflow re-publishes a frozen subject forever | after v26.9.29 ships, retire/parameterize `release-v26.9.28.yml` (or convert to the exact-head court pattern) | M |
| 6 | `test_load_filters` warning: `test/integration/{obda_crown,ontop_compliance_crown}.exs` match no test pattern | rename to `*_test.exs`, add to `test_ignore_filters`, or document exclusion | S |

## Honesty residues

- The count run excludes one file; the exclusion is named and its upstream fix located (`origin/main` diff). The suite-at-origin/main count is implied by hosted CI green but was not re-run locally at `36f25a3` (checkout moves forbidden to this lane).
- `mix test` at local HEAD cannot currently complete at all — that fact outranks any partial count.
- Local `git fetch` updated remote-tracking refs (read-only w.r.t. the working tree; no branch/commit writes by this lane).