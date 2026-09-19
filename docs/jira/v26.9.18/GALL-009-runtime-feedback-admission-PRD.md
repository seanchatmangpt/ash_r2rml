# PRD v26.9.18 — GALL-009: Runtime Feedback Admission

**Status:** DRAFT IMPLEMENTATION SPEC
**Release:** v26.9.18
**Repository:** `seanchatmangpt/ash_r2rml`
**Owner:** ash_r2rml
**Dependencies:** GALL-008 observational evidence, public semantic model
**Authority ceiling:** ADMISSION/CONSTRUCT semantics only; no DO

## Product outcome

Runtime evidence is transformed into explicit candidate RDF deltas, validated against mapping/shape/law constraints, and either admitted into a new semantic subject or typed-refused.

## Problem

Observed runtime evidence can reveal ontology/process gaps, but direct mutation of canonical RDF from telemetry would turn observation into authority. Feedback needs a candidate-to-admitted semantic mapping path.

## Functional requirements

1. Map telemetry/process evidence to candidate RDF using explicit R2RML/RML-style mappings or repository-native equivalent.
2. Keep observed facts, inferred candidate facts and admitted facts as distinct graph classes.
3. Require SHACL/ShEx/SPARQL or equivalent bounded admission checks before a candidate becomes canonical.
4. Bind every delta to source evidence digest and mapping identity.
5. No feedback adapter may directly mutate canonical graph state.
6. Emit accepted/refused delta receipt and exact new graph digest when admitted.

## Acceptance criteria

1. Valid runtime evidence produces deterministic candidate triples and an auditable admitted delta.
2. Invalid/out-of-vocabulary evidence is refused without canonical mutation.
3. Changing mapping identity changes candidate/admission subject.
4. Removing source evidence invalidates delta provenance.
5. Round-trip preserves public vocabulary; no private ontology laundering.

## Evidence product

The checkpoint MUST emit a content-addressed machine-readable receipt/artifact binding exact producer SHA, input/predecessor identities, executed court, falsifiers, outputs, standing and evidence ceiling. Source presence or prose is not standing.

## Non-functional requirements

- Deterministic identity for identical admitted inputs.
- Typed UNKNOWN/PARTIAL/REFUSED/BLOCKED states.
- No ambient authority or undeclared dependency.
- Exact-head subject fencing and replayable evidence.
- No promotion of observation, model output, parsing or configuration into stronger standing.

## Definition of done

Runtime evidence is transformed into explicit candidate RDF deltas, validated against mapping/shape/law constraints, and either admitted into a new semantic subject or typed-refused.
