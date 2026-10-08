# ash_r2rml: land or delete remote branch `ws2/compose-50b-20260827-2008`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `ws2/compose-50b-20260827-2008` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/ash_r2rml --head ws2/compose-50b-20260827-2008`) or delete (`git push origin --delete ws2/compose-50b-20260827-2008`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `ws2/compose-50b-20260827-2008`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | ws2/compose-50b-20260827-2008 | decision pending
