<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Knowledge Hooks reference

Information-oriented catalog of modules, predicate types, receipts, and refusal
surfaces. For tasks see the [how-to](../how_to/knowledge_hooks.md); for learning
see the [tutorial](../tutorials/knowledge_hooks_n3.md).

---

## Public entry points

| Function | Module | Role |
|---|---|---|
| `AshR2RML.admit_knowledge_hooks/2` | `AshR2RML.KnowledgeHooks.admit/2` | Admit definitions → construct-only `Plan` |
| `AshR2RML.evaluate_knowledge_hooks/2` | `AshR2RML.KnowledgeHooks.evaluate/2` | Observe predicates → `Evaluation` / `Intent` |
| `AshR2RML.actuate_knowledge_hook/3` | `AshR2RML.KnowledgeHook.Actuator.actuate/3` | BRCE DO → `ActuationReceipt` |
| `AshR2RML.project_knowledge_hook_target/1` | `AshR2RML.KnowledgeHook.Target.from_intent/1` | Inert typed target projection |
| `AshR2RML.compile_knowledge_hook_specs/1` | `AshR2RML.KnowledgeHook.Spec.from_plan/1` | Canonical content-addressed IR |
| `AshR2RML.evaluate_knowledge_hook_promotion/3` | `AshR2RML.KnowledgeHook.Promotion.evaluate/3` | Cognition→reflex candidate (still UNAUTHORIZED) |
| `AshR2RML.compile_knowledge_hooks_bundle/2` | `AshR2RML.Ggen.KnowledgeHooks.compile/2` | Deterministic ggen path/content graph |

Ontology / shapes: `priv/ontology/knowledge-hooks.ttl`,
`priv/shapes/knowledge-hooks.shacl.ttl`.

---

## Core structs

| Struct | Standing / authority | Meaning |
|---|---|---|
| `KnowledgeHook.Plan` | `:admitted_construct_only` / `:UNAUTHORIZED` | Content-addressed admitted hooks |
| `KnowledgeHook.Intent` | `:constructed_not_actuated` / `:UNAUTHORIZED` | Opaque consequent description |
| `KnowledgeHook.EvaluationReceipt` | blocks `:actuation_authority` | Observed predicate evaluation |
| `KnowledgeHook.ActuationReceipt` | `:actuated_with_receipt` / `:AUTHORIZED` | Independent DO receipt |
| `KnowledgeHook.Target` | inert / `:UNAUTHORIZED` | Typed Reactor/Ash/Oban/… projection |
| `KnowledgeHook.Spec` | `:admitted_construct_only`, ceiling `:CONSTRUCT` | Canonical IR |

`R_h ⇏ R_do`: an evaluation receipt is never an actuation receipt.

---

## Predicate types

| Type | Observes | Malformed refusal |
|---|---|---|
| `:ask` | SPARQL `ASK` truth | `REFUSED_UNPROVEN_EQUIVALENCE` |
| `:result_delta` | Previous vs current `SELECT` result SHA-256 | `REFUSED_UNPROVEN_EQUIVALENCE` |
| `:external_trigger` | Observed trigger receipt (`observed?: true`) | `REFUSED_UNPROVEN_EQUIVALENCE` |
| `:shacl` | SHACL conformance for focus nodes | `REFUSED_INVALID_SHACL_SHAPES_GRAPH` |
| `:threshold` | Bound `SELECT` variable vs numeric bound | `REFUSED_INVALID_BOUND_PREDICATE` |
| `:count` | `SELECT` row count vs numeric bound | `REFUSED_UNSUPPORTED_SPARQL_FEATURE` (non-`SELECT`) |
| `:temporal_window` | `time_field` values vs `evaluated_at` window | `REFUSED_MISSING_EVALUATION_TIME` |
| `:datalog` | Single non-recursive Datalog rule | `REFUSED_INVALID_DATALOG_RULE` |

Unsupported predicate forms are refused, not approximated.

### Predicate shapes

```elixir
%{type: :threshold, query: "SELECT ?n WHERE { … }", variable: "n", comparator: :gte, bound: 10}

%{type: :shacl, shapes_graph: shacl_turtle, focus_nodes: ["https://example.com/x"]}

%{type: :temporal_window, query: "SELECT ?t WHERE { … }", time_field: "t", window: {:hour, :lte, 1}}

%{type: :datalog, datalog_rule: "grandparent(X, Z) :- (X, parentOf, Y), (Y, parentOf, Z)."}
```

`:datalog` is single-rule, non-recursive, no negation/aggregation/stratification.

---

## Actuator contract

`AshR2RML.KnowledgeHook.Actuator.actuate/3` requires:

**Intent**
- `%Intent{}` with `authority: :UNAUTHORIZED`
- `standing: :constructed_not_actuated`
- `requires_actuation_receipt?: true`
- 64-hex `evaluation_receipt_sha256`
- stable `target`

**Authority map**
- `brce?: true`
- `authority_sha256`, `brce_receipt_sha256`, `pre_state_sha256`, `post_state_sha256` (each 64-hex)

**Opts**
- `perform: fn target, payload -> {:ok, observed_effect} | {:error, reason} end` (arity 2)

On success returns `%ActuationReceipt{}` with `authority: :AUTHORIZED`,
`standing: :actuated_with_receipt`, and `evaluation_receipt_sha256` bound to the
intent.

---

## Ambient keys refused at admit

Hook definitions may not carry executable authority keys:

`:handler`, `:callback`, `:executor`, `:execute_fun`, `:run_fun`
(and string variants). Non-inert terms (functions, pids, ports, references,
structs) in the definition or intent payload are refused.

`require_actuation_receipt?: false` is refused.

---

## Interop vocabularies

| Vocabulary | Prefix / NS | Hook path role |
|---|---|---|
| GitVan Graph Hook | `https://gitvan.dev/graph-hook#` | ASK / ResultDelta → opaque pipeline target |
| KNHK | `http://knhk.io/ontology#` | Event/Interval/RdfChange → `:external_trigger` |

Neither vocabulary grants DO authority inside AshR2RML.

---

## Chicago / unit evidence

| Suite | Proves |
|---|---|
| `test/adversarial/knowledge_hooks_actuation_chicago_test.exs` | Full N3-style cycle with live Agent DO |
| `test/adversarial/knowledge_hooks_authority_test.exs` | Ambient callback / receipt-waiver refusals |
| `test/knowledge_hooks_*.exs` | Predicate admit/evaluate coverage |
