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

Break each guard, the named test must fail, restore, it must pass:
field-policy omission (`readable/1` in `obda_in_memory.ex`), `sensitive_attribute?/2`,
actor/tenant forwarding (`read_opts`), and the zero-JDBC guard (add a `lib/` module named `*Ontop*`).

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
