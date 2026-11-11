# R2RML-261110-11: Ingestion Determinism & Ggen Pack Gate Realignment

**Title:** Ingestion Determinism & Ggen Pack Gate Realignment  
**Ticket Key:** `R2RML-261110-11`  
**Type:** Enhancement / Integrity  
**Status:** IMPLEMENTED / VERIFIED  
**Priority:** High  
**Component:** `AshR2RML.Ingestion`, Ggen SPARQL Gates  
**Scope:**
- `lib/ash_r2rml/ingestion.ex`
- `priv/ggen/ash-r2rml-pack/gates/010_required_resource_contract.rq`
- `priv/ggen/ash-r2rml-pack/gates/020_property_contract.rq`
- `test/ingestion_determinism_test.exs`

---

## 1. Context

Under the Chatman equation ($A = \mu(O^*)$), compilation must be a deterministic function ($\mu$): identical inputs must produce byte-identical outputs across independent OS processes, runtimes, and execution orders.

Two sources of non-determinism were identified:
1. **Parser-Generated Blank-Node Labels**: RDF parsers generate internal blank-node identifiers (e.g. `_:b0`, `_:b1`) whose naming depends on parse order. If blank-node labels leak into hashes, IR structures, or emitted code, identical profiles yield divergent digests.
2. **SPARQL Pack Gate Drift**: Ggen marketplace gates `010_required_resource_contract.rq` and `020_property_contract.rq` referenced the obsolete namespace `ar2: <https://ash-r2ml.dev/ns#>` and used `FILTER NOT EXISTS` queries that produced false-positive validation errors against canonical profiles.

---

## 2. Task Requirements

1. **Deterministic Statement Sorting & Hash Normalization (`lib/ash_r2rml/ingestion.ex`)**:
   - Implement `term_sort_key/2` ordering RDF terms deterministically.
   - Strip parser-assigned blank-node prefixes before computing graph hashes.
   - Sort parsed property shapes, identities, actions, and transitions by canonical keys before IR construction.
2. **Process-Independent Determinism Court (`test/ingestion_determinism_test.exs`)**:
   - Author multi-process determinism tests executing `Ggen.compile_turtle_bundle/2` across separate OS processes with shuffled triple ordering and randomized blank-node prefixes (`:rand.seed`).
   - Assert byte-identical bundle file outputs for both `:single` and `:per_resource` layouts.
3. **SPARQL Pack Gate Realignment (`priv/ggen/ash-r2rml-pack/gates/`)**:
   - Realign `010_required_resource_contract.rq`:
     - Update namespace to `PREFIX r2ml: <https://seanchatmangpt.github.io/ash_r2rml#>`.
     - Replace `FILTER NOT EXISTS` with explicit `MINUS` clauses.
     - Validate `sh:targetClass`, `r2ml:ashModule`, `r2ml:tableName`, `r2ml:subjectTemplate`, and `r2ml:identity`.
   - Realign `020_property_contract.rq`:
     - Update namespace to `r2ml:`.
     - Validate `r2ml:ashName`, `sh:datatype` or `sh:class`, `r2ml:storageStrategy`, `r2ml:sourceKey`, and `r2ml:destinationKey`.

---

## 3. Acceptance Criteria

- [ ] Parsing identical RDF statements with shuffled line order and distinct blank-node labels produces identical `SemanticIR` hashes.
- [ ] Two separate OS processes compiling `natfac_slice1.profile.ttl` generate byte-identical output files in both `:single` and `:per_resource` layouts.
- [ ] SPARQL gates in `priv/ggen/ash-r2rml-pack/gates/` parse cleanly and accept conforming shapes without false positives.
- [ ] `mix test test/ingestion_determinism_test.exs` passes 100% with 0 failures.

---

## 4. Verification Method

```bash
mix test test/ingestion_determinism_test.exs
```
