# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksNoActuationChicagoTest do
  @moduledoc """
  Chicago-style falsifiers for the *opposite* of ambient low-stakes DO.

  Claim under test (must fail closed): labeling a Knowledge Hook consequence as
  unimportant / trivial / low-severity must never grant actuation authority,
  disable actuation receipts, or execute a real local side effect merely because
  a predicate matched over a real RDF graph.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHook.Promotion
  alias AshR2RML.KnowledgeHook.Promotion.{Candidate, Evidence}
  alias AshR2RML.KnowledgeHooks

  @ask_query """
  ASK WHERE {
    <https://example.com/thing> <https://example.com/state> <https://example.com/ready>
  }
  """

  @ready_graph RDF.Graph.new([
                 {RDF.iri("https://example.com/thing"), RDF.iri("https://example.com/state"),
                  RDF.iri("https://example.com/ready")}
               ])

  setup do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(counter), do: Agent.stop(counter) end)
    %{counter: counter}
  end

  test "matched unimportant-framed ASK constructs an unauthorized intent without local side effects",
       %{counter: counter} do
    before = Agent.get(counter, & &1)

    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "unimportant-ready",
                 name: "Unimportant ready",
                 trigger_type: :sparql_result,
                 predicate: %{type: :ask, query: @ask_query},
                 intent: %{
                   kind: :pipeline,
                   target: "pipeline://notify-slack-emoji",
                   payload: %{
                     importance: "unimportant",
                     severity: "trivial",
                     consequence_class: "low_stakes"
                   }
                 },
                 provenance: %{importance: :unimportant, auto_actuate?: true}
               }
             ])

    assert plan.authority == :UNAUTHORIZED
    assert plan.standing == :admitted_construct_only

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan, current: [data: @ready_graph, strategy: :local_rdf])

    assert evaluation.matched?
    assert evaluation.intent.target == "pipeline://notify-slack-emoji"
    assert evaluation.intent.payload.importance == "unimportant"
    assert evaluation.intent.authority == :UNAUTHORIZED
    assert evaluation.intent.standing == :constructed_not_actuated
    assert evaluation.intent.requires_actuation_receipt? == true
    assert evaluation.receipt.authority == :UNAUTHORIZED
    assert evaluation.receipt.consequence == :intent_constructed
    assert evaluation.receipt.blocked == [:actuation_authority]
    # Observation steps may be executed; actuation steps must not appear.
    assert :sparql_observation in evaluation.receipt.executed
    assert :ask_evaluation in evaluation.receipt.executed
    refute :actuation in evaluation.receipt.executed
    refute :do in evaluation.receipt.executed

    # No ambient DO occurred: the only live collaborator (Agent) is untouched.
    assert Agent.get(counter, & &1) == before
  end

  test "importance: :unimportant does not waive the actuation-receipt requirement" do
    assert {:error, [refusal]} =
             KnowledgeHooks.admit([
               %{
                 id: "unimportant-unreceipted",
                 name: "Unimportant unreceipted",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: %{
                   kind: :workflow,
                   target: "workflow://harmless-cache-warm",
                   payload: %{importance: "unimportant"}
                 },
                 importance: :unimportant,
                 require_actuation_receipt?: false
               }
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.subject == "unimportant-unreceipted"
    assert refusal.detail =~ "actuation receipt"
  end

  test "unimportant ambient handlers/callbacks are refused at admit time", %{counter: counter} do
    bump = fn -> Agent.update(counter, &(&1 + 1)) end

    for ambient_key <- [:handler, :callback, :executor, :execute_fun, :run_fun] do
      definition =
        Map.merge(
          %{
            id: "unimportant-#{ambient_key}",
            name: "Unimportant #{ambient_key}",
            predicate: %{type: :ask, query: @ask_query},
            intent: "workflow://harmless",
            importance: :unimportant,
            severity: :trivial
          },
          %{ambient_key => bump}
        )

      assert {:error, [refusal]} = KnowledgeHooks.admit([definition])
      assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
      assert refusal.subject == "unimportant-#{ambient_key}"
      assert ambient_key in refusal.evidence.forbidden_keys
    end

    assert Agent.get(counter, & &1) == 0
  end

  test "function payload framed as unimportant still fails inert-data admission", %{counter: counter} do
    assert {:error, [refusal]} =
             KnowledgeHooks.admit([
               %{
                 id: "unimportant-runner",
                 name: "Unimportant runner",
                 predicate: %{type: :ask, query: @ask_query},
                 importance: :unimportant,
                 intent: %{
                   kind: :workflow,
                   target: "workflow://harmless",
                   payload: %{
                     importance: "unimportant",
                     runner: fn -> Agent.update(counter, &(&1 + 1)) end
                   }
                 }
               }
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.subject == "unimportant-runner"
    assert Agent.get(counter, & &1) == 0
  end

  test "promotion of an unimportant reflex candidate remains powerless BRCE (no DO authority)" do
    candidate =
      struct!(Candidate,
        hook_spec_sha256: String.duplicate("1", 64),
        subject: "notify:emoji",
        scope: "low-stakes-notify",
        policy_sha256: String.duplicate("2", 64),
        verifier_sha256: String.duplicate("3", 64),
        class: :reflex,
        compensation: %{fallback: "noop", importance: "unimportant"}
      )

    observations = [
      struct!(Evidence,
        receipt_sha256: String.duplicate("a", 64),
        subject: "notify:emoji",
        scope: "low-stakes-notify",
        policy_sha256: String.duplicate("2", 64),
        verifier_sha256: String.duplicate("3", 64),
        standing: :ALIVE,
        observed?: true,
        postcondition_verified?: true,
        replay_verified?: true,
        positive?: true
      ),
      struct!(Evidence,
        receipt_sha256: String.duplicate("b", 64),
        subject: "notify:emoji",
        scope: "low-stakes-notify",
        policy_sha256: String.duplicate("2", 64),
        verifier_sha256: String.duplicate("3", 64),
        standing: :ALIVE,
        observed?: true,
        postcondition_verified?: true,
        replay_verified?: true,
        positive?: true
      ),
      struct!(Evidence,
        receipt_sha256: String.duplicate("c", 64),
        subject: "notify:emoji",
        scope: "low-stakes-notify",
        policy_sha256: String.duplicate("2", 64),
        verifier_sha256: String.duplicate("3", 64),
        standing: :ALIVE,
        observed?: true,
        postcondition_verified?: true,
        replay_verified?: true,
        falsifier?: true
      )
    ]

    assert {:ok, result} = Promotion.evaluate(candidate, observations)
    assert result.standing == :promotion_candidate
    assert result.authority == :UNAUTHORIZED
    assert result.receipt.blocked == [:actuation_authority]
    assert result.brce_request.authority == :UNAUTHORIZED
    refute result.brce_request.do_authority
    assert result.brce_request.requires_actuation_receipt?
  end

  test "second evaluate of the same unimportant match remains construct-only and non-executing",
       %{counter: counter} do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "unimportant-replay",
                 name: "Unimportant replay",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: %{
                   kind: :pipeline,
                   target: "pipeline://cache-hint",
                   payload: %{importance: "unimportant"}
                 }
               }
             ])

    opts = [current: [data: @ready_graph, strategy: :local_rdf]]
    assert {:ok, [first]} = KnowledgeHooks.evaluate(plan, opts)
    assert {:ok, [second]} = KnowledgeHooks.evaluate(plan, opts)

    assert first.matched? and second.matched?
    assert first.receipt.receipt_sha256 == second.receipt.receipt_sha256
    assert first.intent.authority == :UNAUTHORIZED
    assert second.intent.authority == :UNAUTHORIZED
    assert first.receipt.blocked == [:actuation_authority]
    assert second.receipt.blocked == [:actuation_authority]
    assert Agent.get(counter, & &1) == 0
  end
end
