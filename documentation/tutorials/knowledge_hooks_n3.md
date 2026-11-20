<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Tutorial: N3-style rules in Elixir with Knowledge Hooks

This tutorial walks you through one complete rule cycle — the Elixir analogue of
an N3 implication `{ antecedent } => { consequent }` — using AshR2RML Knowledge
Hooks for the antecedent and `KnowledgeHook.Actuator` for the fire.

You will:

1. Admit a rule whose antecedent is a SPARQL `ASK`
2. Evaluate it against a real `RDF.Graph`
3. See an unauthorized intent constructed (CONSTRUCT only)
4. Actuate that intent under explicit BRCE authority with a real local side effect

---

## What you are learning

```text
N3:   { ?s :state :ready } => { …consequent… } .

Elixir:
  KnowledgeHooks.admit/evaluate  →  Intent  (UNAUTHORIZED)
  KnowledgeHook.Actuator.actuate →  effect + ActuationReceipt  (AUTHORIZED)
```

Hooks never run the consequent. The actuator is the opposite side of that fence.

---

## Prerequisites

- Elixir `~> 1.17` / OTP from `.tool-versions`
- This repository compiled (`mix deps.get && mix compile`)
- Familiarity with basic RDF triples

---

## Step 1: Build a tiny graph

```elixir
graph =
  RDF.Graph.new([
    {RDF.iri("https://example.com/thing"),
     RDF.iri("https://example.com/state"),
     RDF.iri("https://example.com/ready")}
  ])
```

---

## Step 2: Admit the rule (antecedent + opaque consequent)

```elixir
{:ok, plan} =
  AshR2RML.KnowledgeHooks.admit([
    %{
      id: "ready-notify",
      name: "Ready notify",
      trigger_type: :sparql_result,
      predicate: %{
        type: :ask,
        query: """
        ASK WHERE {
          <https://example.com/thing>
          <https://example.com/state>
          <https://example.com/ready>
        }
        """
      },
      intent: %{
        kind: :pipeline,
        target: "pipeline://notify-ready",
        payload: %{channel: "ops"}
      }
    }
  ])

plan.authority
# => :UNAUTHORIZED

plan.standing
# => :admitted_construct_only
```

The `intent` names what *would* follow. It is inert data — not a callback.

---

## Step 3: Evaluate the antecedent

```elixir
{:ok, [evaluation]} =
  AshR2RML.KnowledgeHooks.evaluate(plan,
    current: [data: graph, strategy: :local_rdf]
  )

evaluation.matched?
# => true

intent = evaluation.intent
intent.authority
# => :UNAUTHORIZED

intent.standing
# => :constructed_not_actuated

intent.requires_actuation_receipt?
# => true
```

You now have a constructed consequent description plus an evaluation receipt.
Nothing has been actuated.

---

## Step 4: Fire the consequent (actuator / DO)

```elixir
{:ok, counter} = Agent.start_link(fn -> 0 end)

sha = fn value ->
  :crypto.hash(:sha256, :erlang.term_to_binary(value))
  |> Base.encode16(case: :lower)
end

pre = sha.(Agent.get(counter, & &1))

{:ok, actuation} =
  AshR2RML.KnowledgeHook.Actuator.actuate(
    intent,
    %{
      brce?: true,
      authority_sha256: String.duplicate("a", 64),
      brce_receipt_sha256: String.duplicate("b", 64),
      pre_state_sha256: pre,
      post_state_sha256: sha.(1)
    },
    perform: fn target, payload ->
      Agent.update(counter, &(&1 + 1))
      {:ok, %{target: target, channel: payload.channel, count: Agent.get(counter, & &1)}}
    end
  )

Agent.get(counter, & &1)
# => 1

actuation.authority
# => :AUTHORIZED

actuation.standing
# => :actuated_with_receipt

actuation.evaluation_receipt_sha256 == intent.evaluation_receipt_sha256
# => true
```

The `perform/2` function is admitted only here — never inside the hook definition.

---

## What you should take away

| N3 idea | What you just did in Elixir |
|---|---|
| Antecedent formula | SPARQL `ASK` predicate on a real graph |
| Implication / rule | Admitted Knowledge Hook plan |
| Derived consequent description | `%Intent{}` + evaluation receipt |
| Actually doing something | `Actuator.actuate/3` under BRCE |

---

## Next

- Task recipes: [How to use Knowledge Hooks](../how_to/knowledge_hooks.md)
- Why the fence exists: [Knowledge Hooks thesis](../topics/knowledge_hooks_thesis.md)
- API catalog: [Knowledge Hooks reference](../reference/knowledge_hooks.md)
- Chicago proof of this path: `test/adversarial/knowledge_hooks_actuation_chicago_test.exs`
