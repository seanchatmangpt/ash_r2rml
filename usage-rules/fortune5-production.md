<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors
SPDX-License-Identifier: MIT
-->

# Fortune-5 production usage rules

Use `AshR2RML.Fortune5.ProductionClosure` when a feature claims enterprise or Fortune-5 production standing.

## Required posture

- Preserve topology candidates until one is explicitly selected.
- Treat construction, runtime execution, cutover, and production standing as separate receipts.
- Keep Spark as admission, Reactor as orchestration, Igniter as installation/generation, and ggen as manufacturing.
- Do not let generated RDF, SHACL, SQL, Ash source, or Reactor output actuate without BRCE.
- Do not promote CI metadata, protocol availability, or unit tests into ALIVE unless the exact subject was executed.

## Required checks

A production contract must retain hard checks for SLO, capacity, availability, telemetry, security, operations, authority, and topology. Runtime/cutover checks are separate: exact subject observation, 1M-concurrency stress observation, exact-head CI, OBDA crown receipt, and explicit cutover authority.

## Refusal rules

- Missing BRCE is `REFUSED_UNRECEIPTED_ACTUATION`.
- A failed hard bound is `REFUSED_FORTUNE5_PRODUCTION_BOUND`.
- Attempted DO without BRCE requirement enabled is `REFUSED_AUTHORITY`.
- Missing runtime evidence leaves the contract `PARTIAL_ALIVE`, not `ALIVE`.
