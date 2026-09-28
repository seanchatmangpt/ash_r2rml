# ash_r2rml v26.9.16 — RFC Closure Contract

Status: DRAFT IMPLEMENTATION PR.

## Canonical Jira tickets

- A2A-2608 — projected-ephemeral software invariant
- A2A-2612 — machine-experience compile-back

## RFC ownership

This repo owns semantic projection/parity at the Ash boundary: exact semantic-subject identity must survive graph-to-runtime projection without allowing a projection to become an independent source of truth.

## Required closure

1. Bind generated/runtime projection identity to admitted semantic source, manufacturer identity and projection digest.
2. Preserve parity witnesses across supported projection targets.
3. Make projection drift fail closed: a changed generated/runtime artifact without a corresponding admitted semantic-source change must not silently acquire standing.
4. Accept qualified machine-experience input only as candidate semantic change until admission succeeds.
5. Emit exact evidence consumable by SA2A receipts and cross-repo qualification.

## Chicago falsifiers

- modify a generated projection while preserving its claimed semantic identity;
- cut over without the required parity witness;
- allow runtime/source session identity to cross semantic revisions silently;
- allow receipt feedback to mutate canonical mapping state without admission;
- treat projection success as execution authority.

## Definition of done

Exact-head compile/tests prove source/projection/manufacturer binding, parity fail-closed behavior, candidate-only compile-back, and receipt-compatible evidence. No claim of runtime ALIVE standing is implied by successful projection alone.
