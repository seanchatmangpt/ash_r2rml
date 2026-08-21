<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Permanent production falsifiers

These are counterexamples the production architecture must keep executable.

- ambiguous semantic relationship silently becomes a relational choice;
- unsupported datatype silently becomes a string;
- physical table rename unexpectedly changes RDF identity;
- two identical ggen runs differ;
- generated projection is edited instead of its owning semantic/manufacturing source;
- stale or different-subject evidence is rebound to the current subject;
- a runtime can perform DO without BRCE;
- a DO request lacks idempotency identity;
- quota state is unknown but routing proceeds;
- tenant or residency filters admit an ineligible cell;
- telemetry labels expose tenant IDs, raw queries, IRIs, credentials or subject values;
- a deployment projection contains a Kubernetes Secret;
- a non-BRCE deployment role carries DO authority;
- zone/region loss violates the declared RPO or RTO;
- rollback lacks its own receipt;
- a critical/high dependency advisory is present while production standing is claimed ALIVE;
- CI passes from a contaminated dependency cache but a clean build cannot reproduce it;
- an OBDA/SPARQL parity claim is based on manufactured rows rather than observed execution.
