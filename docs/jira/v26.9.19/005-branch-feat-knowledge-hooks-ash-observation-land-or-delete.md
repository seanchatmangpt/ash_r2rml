# ash_r2rml: land or delete remote branch `feat/knowledge-hooks-ash-observation`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `feat/knowledge-hooks-ash-observation` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/ash_r2rml --head feat/knowledge-hooks-ash-observation`) or delete (`git push origin --delete feat/knowledge-hooks-ash-observation`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `feat/knowledge-hooks-ash-observation`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | feat/knowledge-hooks-ash-observation | decision pending
