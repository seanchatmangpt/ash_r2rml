# R2RML-261110-04: Bidirectional Castle-Bridge Trust Mirror (`castle_bridge_contract.ttl`)

**Title:** Bidirectional Castle-Bridge Trust Mirror (`castle_bridge_contract.ttl`)  
**Ticket Key:** `R2RML-261110-04`  
**Type:** Feature / Integrity  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** Medium  
**Component:** `AshR2RML.CastleBridge`, Ontology, Test Suite  
**Scope:**
- `ontology/castle_bridge_contract.ttl`
- `test/unit/castle_bridge_contract_test.exs`

---

## 1. Context

In accordance with C12 trust-chain symmetry, trust across repositories and ggen-marketplace packs must be reciprocal. Previously, downstream consumer packs pinned `ash_r2rml` commit hashes, but `ash_r2rml` maintained no reciprocal observation of consumer contracts. As a result, changes to `ash_r2rml` could break downstream assumptions without local detection.

This feature establishes an in-repo trust mirror in `ontology/castle_bridge_contract.ttl` along with four strict court tests in `test/unit/castle_bridge_contract_test.exs`.

---

## 2. Task Requirements

1. **Ontology Trust Mirror (`ontology/castle_bridge_contract.ttl`)**:
   - Define four RDF observation subjects mirroring `xcb:bridge`:
     - Castle source repository observation
     - Marketplace pack observation
     - Self-observation (`seanchatmangpt/ash_r2rml`)
     - Consumer base contract observation
   - Document explicit as-of dates and the `MANUAL-SYNC LAW`.
2. **Four Automated Test Courts (`test/unit/castle_bridge_contract_test.exs`)**:
   - **Court 1 (Shape)**: Validate that `ontology/castle_bridge_contract.ttl` conforms to SHACL contract shapes and contains all required RDF statements.
   - **Court 2 (Cross-Check)**: Cross-check mirror observations against live sibling pack contracts if present.
   - **Court 3 (HEAD Match & Staleness Allowlist)**: Assert that observed pins match live HEAD, or are explicitly registered in `@staleness_allowlist` with valid as-of dates and justifications.
   - **Court 4 (Fail-Closed Semantics)**: Ensure unlisted stale pins emit warnings or fail closed, preventing silent pin drift.

---

## 3. Acceptance Criteria

- [ ] `ontology/castle_bridge_contract.ttl` is valid Turtle and parses cleanly with `RDF.Turtle.read_string/1`.
- [ ] Contract observations include all 4 required subjects with exact commit SHAs.
- [ ] Stale observed pins produce `MIRROR_PIN_WARNING` when allowlisted, or fail if un-allowlisted.
- [ ] `mix test test/unit/castle_bridge_contract_test.exs` exits with code 0 (4 tests, 0 failures).

---

## 4. Verification Method

Run the castle-bridge contract test suite:

```bash
mix test test/unit/castle_bridge_contract_test.exs
```
