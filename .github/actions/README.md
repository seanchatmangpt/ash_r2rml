# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Shared GitHub Actions

Local composites used by `.github/workflows/*`. Local actions require
`actions/checkout` first; do not put checkout itself inside a composite that is
invoked as the first step.

| Action | Purpose |
| --- | --- |
| `assert-exact-head` | Refuse if `HEAD` ≠ admitted subject SHA |
| `setup-elixir` | mise from `.tool-versions`, clean `deps`/`_build`, optional lock verify |

Third-party actions are pinned to full commit SHAs with a trailing `# vN` comment.
Dependabot (`.github/dependabot.yml`) refreshes those pins weekly.
