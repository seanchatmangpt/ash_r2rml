<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Production engineering workspace

This directory is **not an AshR2RML application domain** and does not define a runtime namespace.
It is the repository workspace for manufacturing law, quality evidence, falsifiers, and replay instructions that sit outside the semantic compiler itself.

“Fortune 5” was used during design as shorthand for the expected quality level. It is not a class, product tier, ontology term, module prefix, folder name, or deployable component. The implementation uses measurable requirements instead: deterministic manufacture, exact-subject evidence, bounded execution, least privilege, reproducible builds, dependency hygiene, tenant isolation, failure recovery, observable SLOs, and receipted authority.

## Ownership

- `lib/ash_r2rml/` owns reusable compiler and production-admission code.
- `AshR2RML.DfCM` owns generic reversible design-space exploration.
- `AshR2RML.Production` owns measurable technical standing, never business semantics.
- `AshR2RML.Ggen.Production` constructs dynamic model inputs from the admitted subject.
- `production/ggen/` owns ggen gates, queries and templates.
- ggen owns final development-time rendering/filesystem receipts.
- BRCE remains the only DO authority boundary.

The checked-in ggen workspace intentionally has no checked-in `input.ttl`. That file is a deterministic projection returned by `AshR2RML.Ggen.Production.compile/2`. This prevents a second hand-maintained semantic truth from appearing under `production/`.

## Verification order

1. compile with warnings as errors;
2. run DfCM and production admission tests;
3. parse dynamic Turtle independently;
4. materialize the returned `production/ggen/input*` files;
5. run ggen gates and generation twice;
6. require byte-identical second-pass output;
7. run relational/OBDA behavioral crowns;
8. run load, failover, DR, dependency-audit and rollback evidence;
9. only then evaluate technical production standing;
10. keep DO authorization separate and BRCE-bound.
