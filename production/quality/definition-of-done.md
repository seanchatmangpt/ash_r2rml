<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Production quality definition of done

A production-quality claim is valid only for an exact semantic subject and exact environment identities represented by receipts.

## Semantic integrity

- Ash-first and ontology-first entry paths converge on canonical Mapping IR.
- R2RML and SHACL parse with independent standards parsers.
- subject identity, datatype, relationship and join falsifiers remain permanent.
- generated operational projections never become semantic source-of-truth.

## Manufacturing integrity

- ggen receives dynamic inputs generated from the admitted subject.
- gates execute before projection writes.
- SELECT queries used for deterministic generation contain explicit ordering.
- two identical runs are byte-identical except explicitly declared receipt metadata.
- staged file hashes match the construction receipt exactly.

## Runtime quality

- P99 cold path target is at most 500 ms for the admitted workload class.
- the stated scale target is at least 1,000,000 concurrent operations.
- queueing, timeouts, retries, output bytes and result rows are bounded.
- multi-zone and multi-region failover are observed, not inferred.
- disaster recovery replay has measured RPO/RTO evidence.
- telemetry connects trace identity to semantic and execution receipt identity without high-cardinality sensitive labels.

## Security and supply chain

- zero ambient DO authority.
- least privilege and tenant default-deny are verified.
- secrets are externalized and absent from generated plans/receipts.
- known critical and high vulnerabilities are zero at the admitted release head.
- an SBOM, immutable artifact digest, signature and provenance attestation exist.

## Release and authority

- migrations dry-run before application.
- rollback is rehearsed and separately receipted.
- technical production standing does not imply deployment or cutover permission.
- DO requires an explicit BRCE receipt binding authority, pre-state, post-state and replay plan.
