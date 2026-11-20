<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# How to use Knowledge Hooks

Task recipes for admitting, evaluating, and actuating Knowledge Hooks.
For the learning path, see the [N3-style tutorial](../tutorials/knowledge_hooks_n3.md).
For API tables and refusal codes, see the [reference](../reference/knowledge_hooks.md).

---

## Admit and evaluate a hook

```elixir
hooks = [
  %{
    id: "customer-ready",
    name: "Customer ready",
    trigger_type: :sparql_result,
    predicate: %{
      type: :ask,
      query: """
      ASK WHERE {
        <https://example.com/customer/42>
        <https://example.com/state>
        <https://example.com/ready>
      }
      """
    },
    intent: %{
      kind: :reactor,
      target: "MyApp.CustomerReadyReactor",
      payload: %{customer_id: 42}
    }
  }
]

{:ok, plan} = AshR2RML.KnowledgeHooks.admit(hooks)

{:ok, evaluations} =
  AshR2RML.KnowledgeHooks.evaluate(plan,
    current: [data: graph, strategy: :local_rdf]
  )
```

Matched evaluations yield `%AshR2RML.KnowledgeHook.Intent{}` with
`authority: :UNAUTHORIZED` and `requires_actuation_receipt?: true`.

---

## Actuate a constructed intent (opposite side)

```elixir
intent = hd(evaluations).intent

{:ok, actuation} =
  AshR2RML.KnowledgeHook.Actuator.actuate(
    intent,
    %{
      brce?: true,
      authority_sha256: authority_sha,
      brce_receipt_sha256: brce_sha,
      pre_state_sha256: pre_sha,
      post_state_sha256: post_sha
    },
    perform: fn target, payload ->
      MyApp.Notify.deliver(target, payload)
    end
  )
```

`perform/2` is admitted only at this boundary. Embedding callbacks in the hook
definition is refused at `admit/2`.

Public alias: `AshR2RML.actuate_knowledge_hook/3`.

---

## Evaluate a result-delta hook

Provide both previous and current observation contexts — history is never invented:

```elixir
{:ok, evaluations} =
  AshR2RML.KnowledgeHooks.evaluate(plan,
    previous: [data: old_graph, strategy: :local_rdf],
    current: [data: new_graph, strategy: :local_rdf]
  )
```

The hook matches only when normalized SPARQL result SHA-256 identities differ.

---

## Evaluate an external-trigger hook

Event / interval / RDF-change hooks need an observed trigger receipt:

```elixir
AshR2RML.KnowledgeHooks.evaluate(plan,
  trigger_receipts: %{
    "https://example.com/hook" => %{
      observed?: true,
      receipt_sha256: "...stable identity..."
    }
  }
)
```

---

## Evaluate a temporal-window hook

Supply a real `%DateTime{}` as `evaluated_at` — never rely on an internal clock:

```elixir
AshR2RML.KnowledgeHooks.evaluate(plan,
  current: [data: graph, strategy: :local_rdf],
  evaluated_at: DateTime.utc_now()
)
```

---

## Ingest GitVan or KNHK Turtle

```elixir
{:ok, plan} = AshR2RML.KnowledgeHooks.from_turtle(hook_turtle)
```

GitVan pipelines and KNHK actions remain opaque intent targets. AshR2RML does
not execute them from the hook path.

---

## Project a ggen bundle (no filesystem write)

```elixir
{:ok, bundle} = AshR2RML.Ggen.KnowledgeHooks.compile(plan)
```

Produces `generated/knowledge-hooks/plan.json` and
`receipts/knowledge-hooks-compilation.json` as path/content data only.

---

## Related

- Tutorial: [N3-style rules in Elixir](../tutorials/knowledge_hooks_n3.md)
- Explanation: [Knowledge Hooks thesis](../topics/knowledge_hooks_thesis.md)
- Reference: [Knowledge Hooks API](../reference/knowledge_hooks.md)
