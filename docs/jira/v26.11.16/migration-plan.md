# ash_r2rml migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/ash_r2rml
- Remote: https://github.com/seanchatmangpt/ash_r2rml
- Branch: main@225bf30 (tracks origin/main, ahead 3 / behind 0)
- Last commit: 2026-11-11 ("feat(semantic): default_accept + explicit primary create/update")
- Commits: 1346; size 803 MB
- Languages/build: Elixir (mix.exs, mix.lock), ggen.toml, docker-compose.yml
- Nested repos: none

## Observed state
- Dirty: 3 modified -- CHANGELOG.md, ggen.toml, test/unit/ggen_runtime_ancestry_test.exs
- Untracked: 6 -- docs/jira/v26.11.11/, docs/jira/v26.11.12/ (and their contents)
- Ahead of origin/main by 3 commits (unpushed)
- Local branches: 15; 9 unpushed per census. Notable: epoch/v26.9.15-semantic-subject
  ahead 21 of its upstream; feat/ash-r2rml-rename-and-equivalence upstream is "gone";
  feat/graphql-query-only-projection, integrate2..6/*, local-merge have no upstream.
- Stash count: 0
- Build dirs: seven per-agent build trees _build_audit (146M), _build_dan (81M),
  _build_joe (81M), _build_jose (146M), _build_tim (81M), _build_victory (146M),
  _build_zach (81M) -- ~760 MB total, nearly the whole repo size. No _build/ or deps/.
- Release tarballs: ash_r2rml-26.9.28.tar, -26.11.10.tar, -26.11.11.tar (1.3M each)
- Submodules: none; no .env/.db at top level

## What it is
AshR2RML is an Ash (Elixir) extension that compiles Ash resources and semantic annotations
into W3C R2RML mappings, keeping PostgreSQL relational while exposing the same state as a
virtual RDF graph via an OBDA engine such as Ontop. Not a data layer or SPARQL engine.

## Classification
ACTIVE (census agrees; most-recent commit in the lane).

## Migration risk
- 3 uncommitted modified files + 2 untracked jira dirs (release notes).
- 3 unpushed commits on main; 21 unpushed on epoch/v26.9.15-semantic-subject; several
  integrate*/ and local-merge branches with no remote.
- Release tarballs are local-only artifacts (reproducible from tags, low value).
- Rate: HIGH

## Recommended action
COMMIT-PUSH

1. `git add CHANGELOG.md ggen.toml test/unit/ggen_runtime_ancestry_test.exs docs/jira/`
   then `git commit -m "chore(v26.11.16): pre-migration checkpoint"` and `git push origin main`.
2. Push unpushed branches: `git push origin epoch/v26.9.15-semantic-subject` and
   `git push -u origin feat/graphql-query-only-projection integrate2/ws2-contract-guards
   integrate3/release-v26-8-22-integration integrate4/ws5c04 integrate5/ws5c04
   integrate6/orthogonal01 local-merge`.
   DECISION: the integrate*/local-merge branches look like one-off merge scratch; Sean may
   prefer to delete them instead of pushing.
3. Safety bundle: `git bundle create /Volumes/ARCHIVE/ash_r2rml.bundle --all`.
4. Cleanup before any copy: `rm -rf _build_audit _build_dan _build_joe _build_jose _build_tim
   _build_victory _build_zach tmp` (~760 MB). DECISION: keep or drop the three *.tar files.
5. Clone fresh on the new machine.

## First commands on the new machine
- `git clone https://github.com/seanchatmangpt/ash_r2rml && cd ash_r2rml`
- `mix deps.get && mix compile && mix test` (stated, not run)

## See Also
- ../v26.11.12/ (previous jira dir)
- /Users/sac/docs/jira/v26.11.16/README.md (master index)
