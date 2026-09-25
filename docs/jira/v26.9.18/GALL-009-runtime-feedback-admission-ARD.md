# ARD v26.9.18 — GALL-009: Runtime Feedback Admission

**Status:** FINAL_SPEC — closed for v26.9.24
**Implementation standing:** OPEN in PR #40
**Release:** v26.9.18
**Repository:** `seanchatmangpt/ash_r2rml`
**Owner:** ash_r2rml
**Dependencies:** GALL-008 observational evidence, public semantic model
**Authority ceiling:** ADMISSION/CONSTRUCT semantics only; no DO

## Architecture objective

Runtime evidence is transformed into explicit candidate RDF deltas, validated against mapping/shape/law constraints, and either admitted into a new semantic subject or typed-refused.

## Components

- runtime-evidence input schema
- R2RML mapping compiler/executor
- candidate graph partition
- admission/shape gate
- delta receipt + graph digest emitter

## Control/data flow

`Semantic telemetry/observer evidence -> mapping -> candidate RDF delta -> shape/law admission -> admitted O*' or REFUSED -> receipt`

## Invariants

1. Map telemetry/process evidence to candidate RDF using explicit R2RML/RML-style mappings or repository-native equivalent.
2. Keep observed facts, inferred candidate facts and admitted facts as distinct graph classes.
3. Require SHACL/ShEx/SPARQL or equivalent bounded admission checks before a candidate becomes canonical.
4. Bind every delta to source evidence digest and mapping identity.
5. No feedback adapter may directly mutate canonical graph state.
6. Emit accepted/refused delta receipt and exact new graph digest when admitted.

## Failure/refusal boundaries

- Missing mapping => UNSUPPORTED
- Shape/law violation => REFUSED
- Private vocabulary required => REFUSED unless publicly admitted
- Canonical graph write attempted before admission => architecture failure

## Qualification court

- mix format --check-formatted
- mix compile --warnings-as-errors
- focused mapping/admission tests
- round-trip RDF fixture
- full `mix test` relevant suite

## Evidence boundary

Every PASS binds exact producer and predecessor identities. A changed SHA, mapping, model, lockfile, observation projection or runtime subject is a changed subject. A gate is PASS only from observed execution and its required falsifier, never from absence of evidence.

## Authority law

[
Received \neq Admitted,\quad Candidate \neq Authority,\quad SELECT \neq CONSTRUCT \neq DO
]

No component may gain authority merely because it generated, predicted, observed, validated, replayed or parsed something.

## Closure

Architectural closure requires the positive witness plus each named negative witness on the exact v26.9.18 subject.
