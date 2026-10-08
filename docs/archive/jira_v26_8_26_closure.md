# AshR2RML v26.8.26 — Closure Crown

**Release:** `26.8.26`  
**Repository:** `seanchatmangpt/ash_r2rml`  
**Admitted base:** `263aa768bbc5a933124409ee68f2b9efb9d09a3a`  
**Release branch:** `release/v26.8.26`  
**Release PR:** #19  
**Status:** qualification in progress; publication not yet authorized

This document is the v26.8.26 closure addendum. It supersedes the earlier roadmap's statement that R2RML-109 would be deferred to v26.8.27. The research finding changed the release boundary: a demonstrated plaintext disclosure through the InMemory semantic surface is a release-blocking authority defect and is therefore closed in v26.8.26.

## Governing invariant

```text
RDF disclosure ⊆ admitted Ash attribute disclosure
```

An Ash process being able to read a value is not sufficient authority to publish that value into RDF. Semantic publication is a distinct boundary.

## R2RML-109 — CLOSED IN CANDIDATE

### Observed falsifier

`ash_cloak` removes the original encrypted attribute, stores ciphertext in a sensitive `encrypted_<name>` attribute, and installs a sensitive decrypting calculation under the original public name. With `decrypt_by_default`, ordinary `Ash.read!/2` loads that calculation. Prior to this release, `AshR2RML.OBDA.InMemory` treated any loaded struct value under a mapped predicate name as publishable and could therefore materialize plaintext into the RDF graph.

### Repair

`AshR2RML.Security.sanitize_in_memory_mapping/2` is now an obligatory pre-materialization admission transform. For every mapped scalar predicate, the mapped name must still resolve through `Ash.Resource.Info.attribute/2` on the compiled resource. If it does not, the predicate map is removed before row materialization and the exclusion is recorded under:

```elixir
mapping.metadata[:in_memory_non_attribute_excluded_attributes]
```

This is deliberately extension-agnostic. Calculations, aggregates, or extension-manufactured derived fields receive no ambient RDF publication authority merely because they are present in a loaded Ash record.

`AshR2RML.OBDA.InMemory.materialize_many/2` sanitizes all supplied mappings before building the mapping index or reading rows, so graph construction never receives the excluded predicate map.

### Regression proof

`test/obda_in_memory_cloak_test.exs` uses a real `AshCloak` extension on a real `Ash.DataLayer.Ets` resource and verifies three distinct facts:

1. the dangerous precondition is real: ordinary `Ash.read!/2` exposes the decrypted plaintext when `decrypt_by_default` is configured;
2. the public mapped name is a calculation rather than an Ash attribute and the security admission transform removes and receipts it while preserving ordinary admitted attributes;
3. both RDF materialization and SPARQL querying expose zero plaintext/secret-predicate results while a normal mapped `:name` remains queryable.

`ash_cloak ~> 0.3.1` is test-only. No new runtime dependency is introduced.

## Other v26.8.26 delivered work

The previously completed v26.8.26 work remains part of this release:

- real `AshCsv.DataLayer` and `AshCubDB.DataLayer` materialization/SPARQL verification, proving `OBDA.InMemory` is data-layer-agnostic rather than ETS-only;
- corrected InMemory documentation to match the observed architecture;
- `AshR2RML.Ggen.compile_api_bundle/2`, deriving real GraphQL and JSON:API DSL blocks from canonical mapping IR;
- `ash_graphql` and `ash_json_api` retained strictly as test-only verification dependencies;
- five-agent Ash ecosystem research findings retained for follow-on work, including archival asymmetry, PROV-O/paper-trail opportunity, OCEL2/events differentiation, and prior-art analysis.

## Qualification gates

v26.8.26 adds a database-free `release-security` GitHub Actions job that executes the package-level release path independently of inherited external control-plane topology:

```text
mix deps.get
→ mix format --check-formatted
→ mix compile --force --warnings-as-errors
→ mix test --exclude external
→ mix hex.build
```

The inherited `test`/`obda` jobs currently invoke `docker compose`, but the admitted repository tree contains no Compose configuration. Their resulting `no configuration file provided: not found` failure is a classified CI-topology defect, not evidence against the v26.8.26 subject. The new gate exists so package/security qualification cannot be silently skipped by that unrelated external-infrastructure failure.

REUSE qualification also exposed three pre-existing unannotated files. `REUSE.toml` now covers them explicitly, including the historical binary tarball without mutating its bytes.

## Publication boundary

The release workflow is consequential: pushing a `v*` tag invokes `mix hex.build` and then `mix hex.publish --yes` when `HEX_API_KEY` is present. Therefore a tag is publication authority, not a harmless validation operation. v26.8.26 is not considered published until the candidate is merged and an explicitly authorized `v26.8.26` tag is created on the intended release commit.

## Remaining follow-on tickets

These are not R2RML-109 blockers and remain separate work:

- archival soft-delete parity between Ash-mediated InMemory reads and direct Ontop/JDBC reads;
- optional `ash_paper_trail` → PROV-O projection;
- `ash_events`/OCEL2 integration decisions that preserve OCEL2 process-mining semantics.

## Falsifiers

The v26.8.26 security claim must be withdrawn if any of the following is observed on the exact candidate:

- the known plaintext appears anywhere in the materialized RDF graph;
- SPARQL returns a binding for the excluded secret predicate;
- the ordinary mapped `:name` field is lost as collateral damage;
- a mapped non-attribute field reaches graph construction despite the exclusion receipt;
- the package cannot compile with warnings as errors or `mix hex.build` fails;
- a later Ash/AshCloak version changes the transformer semantics such that the admission predicate no longer describes the executed resource.
