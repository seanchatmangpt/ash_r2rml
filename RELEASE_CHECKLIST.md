<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# RELEASE_CHECKLIST

A gate counts only with its exit code and output captured from the exact SHA being tagged.
`release.yaml` additionally refuses to publish unless the `test`, `types` and `release-security`
check runs are green for the tagged SHA and the SHA is an ancestor of `origin/main`.

## Gates (run on a clean checkout of the tag SHA)

| Gate | Command |
|---|---|
| Format | `mix format --check-formatted` |
| Compile | `mix compile --force --warnings-as-errors` |
| Dialyzer | `mix dialyzer` |
| Tests | `mix test --warnings-as-errors` |
| Package | `mix hex.build --unpack -o <dir>` then `find <dir> -type f \| grep -iE 'jdbc\|ontop\|\.jar'` must print nothing |
| Zero JDBC in source | `grep -rliE 'jdbc\|ontop' lib mix.exs` must print nothing |
| CI | every job on the SHA is `success` (CI, REUSE, Exact-head release court) |
| Remote | `git ls-remote origin refs/heads/main \| grep <sha>` |
| Tag | `git ls-remote --tags origin \| grep <tag>` peels to `<sha>` |
| Hex | `https://hex.pm/packages/ash_r2rml/<version>` serves the version; unpacked tarball has no jdbc/ontop/jar |

## Mutation court (non-vacuity)

Run `bin/mutation-court` on a clean tree (preflight exits 2 when `git status --porcelain` is
non-empty). Each mutation breaks one guard in place, the named test must fail, the file is
restored (`git checkout --`) and the tree re-verified clean, then the test must pass again. A
test that passes under mutation exits 1 as `VACUOUS_TEST_DETECTED`. The court ends with
`git diff --exit-code`.

| Mutation | Break | Test that must fail |
|---|---|---|
| M1 | field-policy omission (`readable/1` in `obda_in_memory.ex` leaks `ForbiddenField`) | `test/data_layer_contract_test.exs` |
| M2 | `sensitive_attribute?/2` always false | `test/data_layer_contract_test.exs` |
| M3 | actor/tenant forwarding (`:tenant` dropped from the `Ash.read` options) | `test/data_layer_contract_test.exs` |
| M4 | zero-JDBC guard (add `lib/ash_r2rml/ontop_mutant.ex`) | `test/zero_jdbc_guard_test.exs` |
| M5 | Reactor compensation (`undo(:always)` removed from `test/reactor_semantic_test.exs`) | `test/reactor_semantic_test.exs` |

Exit codes: 0 all killed and tree clean, 1 vacuous test or red baseline, 2 dirty preflight,
3 mutation not applied, 4 restore left the tree dirty, 5 final `git diff` not empty.

## Data-layer contract

`test/data_layer_contract_test.exs` and `test/cross_layer_equivalence_test.exs` compile one
canonical Organization (composite `{tenant_id}/{code}` subject, `:attribute` multitenancy,
sensitive `internal_tax_id`) and Person (field policy on `secret_note`, sensitive `ssn_token`)
onto ETS (always), AshSqlite (tag `:sqlite`, present only when `ash_sqlite` is a dependency) and
Postgres (tag `:postgres`, excluded unless `ASH_R2RML_POSTGRES_URL` is set), and require
byte-identical R2RML across input order, subject IRI round trip for `acme/west #1`, equal
canonical bindings across layers, and admin/member/outsider/nil-actor/tenant isolation.

## Accepted gaps (named, not hidden)

- `mix credo --strict` is not clean (119 findings at `ea71c16`, mostly `resource.ex` and
  `introspection.ex`); not part of the release gate.
- OBDA against an external SPARQL-to-SQL engine is UNVERIFIED by design (Ontop/JDBC removed).
- Tests `workstation2_contract` 17-20, 39, 40, 41 assert `AGENTS.md` text only; no behavioral test yet.
- `SPARQL.Protocol` blocks literal private/loopback hosts but does no DNS resolution (hostname
  pointing at a private address is not blocked).
- Ash `scoped_caller` in `ash_a2a` yields a principal key, not an Ash actor; the mapping is unwritten.
- `OBDA.InMemory` row order is unspecified (SPARQL semantics; `ORDER BY` is honored). For stable
  digests use `AshR2RML.SPARQL.Result.hash_rows/1`, which is order-insensitive; do not hash raw row lists.
