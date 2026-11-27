# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

# Gap closure plan for 2027 (v27.*)

**Standing:** PLAN (not ALIVE)  
**Observed base:** `origin/main` @ `0ea4246`  
**Sources (in precedence order):** live CI + `test/` + `lib/`, then README named gaps,
`docs/jira/v26.11.12/TODO-FIX-AND-FINISH.md`, VKG residual section, production falsifiers,
open PR debt.

This plan answers: **how** to close every closable gap before claiming CalVer 2027 readiness.
It does **not** redefine AshR2RML as a graph DB, network federation product, or ambient actuator.

---

## North star

```text
PARTIAL_ALIVE (honest product today)
        │
        ▼  P0–P1 courts + fail-closed hygiene
BUILD_GREEN main + Hex-ready package courts
        │
        ▼  P2 product gaps closed or re-named
v27.0.0 admitted with explicit residual gaps
        │
        ▼  P3 optional expansions (only with evidence)
v27.* ALIVE lanes where exact-head proves them
```

**Definition of “closed”:** exact-head command(s) exit 0, typed refusal or receipt shape exists,
falsifier named, README/AGENTS updated to match reality (no stale “open gap” prose).

**Definition of “durable named gap”:** intentionally not built; documented once; has a
falsifier that would fire if someone silently “implements” it without evidence.

---

## Gap inventory (current)

### A. Blocking courts — `main` is not green

| ID | Gap | Evidence | Close path |
| --- | --- | --- | --- |
| **G-CI-01** | Dialyzer `types` job fails | `admission.ex:430` guard_fail; `knowledge_hook/actuator.ex` unknown `Intent.t/0`; `obda_in_memory.ex` pattern_match vs stale `.dialyzer_ignore.exs` line | Fix typespecs / ignore drift; `mix dialyzer` clean |
| **G-CI-02** | AIRo W685 cross-repo pin uses laptop path | `test/airo_wiring_ledger_pin_w685_test.exs` → `/Users/sac/xaas/...` | Gate behind `File.exists?` + `:external`/CI skip, or vendor pin-only assertion (fixture sha already tested) |
| **G-CI-03** | Ggen ancestry pin resolution flaky under shallow clone | Fixed on #57 for ancestry jobs; confirm on `main` after merge | Merge CI hygiene PR; keep `fetch-depth: 0` on pin courts |
| **G-CI-04** | Duplicate / divergent specialist workflows | Pre-#57: mise@v2 vs v4, cache vs no-cache, ubuntu-latest | Land #57 best-practices rewrite |

**Lane exit:** `mix compile --warnings-as-errors && mix dialyzer && mix test --exclude external` green in CI exact-head.

### B. Fail-closed / security hygiene (TODO-FIX-AND-FINISH)

| ID | Severity | Gap | Close path |
| --- | --- | --- | --- |
| **G-SEC-01** | HIGH | Raw `postgres_type` interpolated into DDL (`ingestion` → `semantic_renderers`) | Allowlist + quote/refuse hostile literals; adversarial test |
| **G-SEC-02** | MED | `storageStrategy` `other -> other` fail-open | Fail closed with typed refusal |
| **G-SEC-03** | MED | `Module.concat` / atom admission on ingested strings | Route through existing `safe_atom` |
| **G-SEC-04** | MED | `Code.eval_string` over Livebooks | Allowlist cells only; refuse otherwise |
| **G-SEC-05** | LOW | `Process.sleep` in tests | Replace with deterministic sync or delete |
| **G-SEC-06** | DECIDE | Staleness allowlist has hardcoded `@today` / no expiry | Policy: max age + UTC date source; failing court when expired |

**Lane exit:** each HIGH/MED has a negative test that refuses the bad input; `rg` courts for sleep/eval as agreed.

### C. Product named gaps (README / AGENTS honesty)

| ID | Gap | Decision for v27 | Close path if closing |
| --- | --- | --- | --- |
| **G-PROD-01** | README still calls `:temporal_window` / `:datalog` “not yet designed” while later claiming 8 predicates ALIVE | **Docs drift** — fix README immediately | Single Status section; remove contradictory paragraphs |
| **G-PROD-02** | `:datalog` single-rule only | **Durable named gap** unless product chooses engine | If expand: recursive/negation scope PRD + Chicago suite; else keep named |
| **G-PROD-03** | `Ash.Type.Range` / duration mapping | **Close** once Ash lock already has Range (CHANGELOG notes 3.32+) | Datatype registry + round-trip + refusal tests |
| **G-PROD-04** | Federation = in-process determinism only | **Durable named gap** (not network federation) | Keep; do not market as multi-tenant |
| **G-PROD-05** | VKG live Ontop residual | **Partial close** | Dedicated CI job or documented `:external` with docker-compose; residual risks stay named |
| **G-PROD-06** | Knowledge Hook Actuator is construct→BRCE DO | **Close docs + Hex surface** | Ensure README Status mentions Actuator; public API already on #56 |
| **G-PROD-07** | Join-table many-to-many → typed refusal | **Durable** unless product adds assoc-table IR | Keep refusal; optional later epic |

### D. Governance / release debt

| ID | Gap | Close path |
| --- | --- | --- |
| **G-GOV-01** | Open stale PRs (#50, #39, …) | Merge, rebase, or close with receipt |
| **G-GOV-02** | Local-only migration notes (`v26.11.16`) | Archive or execute COMMIT-PUSH hygiene once |
| **G-GOV-03** | Hex publish only via `v*` tags | Keep; require green P0 before any `v27.0.0` tag |
| **G-GOV-04** | Ten-persona review ACTIVE but not a court | Convert must-fix findings into tickets; rest → named deferrals |

### E. Intentionally not gaps (do not “close” by building)

- Graph DB / SPARQL optimizer / OWL reasoner
- Ambient hook actuation without BRCE
- Ontop JDBC gaining Ash actor context (closed structurally via `sanitize_mapping/2`)
- Network federation protocol under `AshR2RML.Federation`

---

## Execution sequence (how to close)

### Wave 0 — Unblock `main` (blocking)

1. Merge [#57](https://github.com/seanchatmangpt/ash_r2rml/pull/57) (GHA best practices + ancestry `fetch-depth`).
2. Fix **G-CI-01** Dialyzer (actuator `Intent` typespec export; admission guard; ignore line sync).
3. Fix **G-CI-02** AIRo path (CI-safe pin court).
4. Re-run full ladder; only then call courts green.

### Wave 1 — Fail-closed compiler (security)

1. **G-SEC-01** postgres_type allowlist (highest blast radius).
2. **G-SEC-02** + **G-SEC-03** storageStrategy / atom admission.
3. **G-SEC-04** Livebook eval allowlist.
4. **G-SEC-06** pin expiry policy.

### Wave 2 — Product honesty + datatype

1. **G-PROD-01** README/AGENTS single source of truth for Knowledge Hooks + Status.
2. **G-PROD-03** `Ash.Type.Range` (and Duration if admitted) mapping.
3. **G-PROD-06** document Actuator N3 cycle in Status (already Diátaxis’d).
4. Re-admit **G-PROD-02/04/05/07** as durable named gaps with one-line falsifiers each.

### Wave 3 — 2027 optional expansions (only with PRD)

Pick **at most one** per minor:

- Broader Datalog (engine decision) — large
- VKG live Ontop crown in required CI — infra
- Assoc-table many-to-many IR — semantic IR change
- True multi-env Federation beyond in-process — out of product invariant unless product changes

### Wave 4 — Tag `v27.0.0`

1. Version carriers (`mix.exs`, `ggen.toml`, CHANGELOG) → `27.0.0`.
2. Exact-head release court green.
3. Tag `v27.0.0` → Hex via `release.yaml` only.
4. Receipt: standing per lane; residual named gaps listed; no PARTIAL_ALIVE marketed as ALIVE.

---

## Verification ladder (re-derive at admitted SHA)

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix dialyzer
mix test test/unit/
mix test test/adversarial/ test/negative/
mix test --exclude external
mix test test/fortune5/
# live crowns when topology present:
mix test test/adversarial/ontop_postgres_test.exs
mix test test/adversarial/reactor_saga_test.exs
mix hex.build
```

CI supplements; it is not truth.

---

## Ownership map (suggested)

| Wave | Owner lens | Modules |
| --- | --- | --- |
| 0 | CI / types | `.github/**`, `.dialyzer_ignore.exs`, `actuator.ex`, `admission.ex`, AIRo test |
| 1 | Compiler security | `ingestion.ex`, `semantic_renderers.ex`, Livebook task |
| 2 | Product docs + datatypes | `README.md`, `AGENTS.md`, `datatype_registry.ex` |
| 3 | Epic PRDs | VKG / Datalog / M2M — new tickets under `docs/jira/v27.*` |
| 4 | Release | `release.yaml`, CHANGELOG, tag |

---

## Falsifiers for this plan

- Claiming v27 readiness while `types` / `release-security` / `test` fail on exact head.
- Closing a “named gap” by deleting the sentence without a test or durable-gap admission.
- Expanding Federation/VKG marketing beyond in-process / observe-only evidence.
- Tagging `v27.0.0` from a dirty tree or non-CI Hex publish.

---

## Immediate next actions

1. Land Wave 0 (CI green) — start with Dialyzer + AIRo pin court.
2. Keep this directory as the living v27 backlog index; tick IDs as PRs merge.
3. Do not start Wave 3 until Waves 0–2 have receipts.
