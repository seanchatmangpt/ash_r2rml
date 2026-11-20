# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksActuationChicagoTest do
  @moduledoc """
  Chicago-style example of the *opposite side* of Knowledge Hooks.

  Hooks stay construct-only. This suite shows the admitted actuation path:

      real RDF graph
        -> KnowledgeHooks.admit/evaluate
        -> unauthorized Intent + evaluation receipt
        -> KnowledgeHook.Actuator.actuate/3 under explicit BRCE authority
        -> real local side effect (Agent) + ActuationReceipt

  Real collaborators only; zero mocks.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHook.Actuator
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

  test "hook match alone constructs an intent; BRCE actuator performs the real side effect",
       %{counter: counter} do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "ready-notify",
                 name: "Ready notify",
                 trigger_type: :sparql_result,
                 predicate: %{type: :ask, query: @ask_query},
                 intent: %{
                   kind: :pipeline,
                   target: "pipeline://notify-ready",
                   payload: %{channel: "ops", mode: "example"}
                 }
               }
             ])

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan, current: [data: @ready_graph, strategy: :local_rdf])

    assert evaluation.matched?
    intent = evaluation.intent
    assert intent.authority == :UNAUTHORIZED
    assert intent.standing == :constructed_not_actuated
    assert intent.requires_actuation_receipt?
    assert Agent.get(counter, & &1) == 0

    pre = sha(Agent.get(counter, & &1))

    assert {:ok, actuation} =
             Actuator.actuate(
               intent,
               %{
                 brce?: true,
                 authority_sha256: String.duplicate("a", 64),
                 brce_receipt_sha256: String.duplicate("b", 64),
                 pre_state_sha256: pre,
                 post_state_sha256: sha(1)
               },
               perform: fn target, payload ->
                 assert target == "pipeline://notify-ready"
                 assert payload.channel == "ops"
                 Agent.update(counter, &(&1 + 1))
                 {:ok, %{delivered?: true, count: Agent.get(counter, & &1)}}
               end
             )

    assert Agent.get(counter, & &1) == 1
    assert actuation.authority == :AUTHORIZED
    assert actuation.standing == :actuated_with_receipt
    assert actuation.consequence == :external_effect_observed
    assert actuation.evaluation_receipt_sha256 == intent.evaluation_receipt_sha256
    assert actuation.hook_id == "ready-notify"
    assert actuation.target == "pipeline://notify-ready"
    assert actuation.observed_effect == %{delivered?: true, count: 1}
    assert :actuation in actuation.executed
    assert is_binary(actuation.receipt_sha256)
    assert byte_size(actuation.receipt_sha256) == 64
    refute actuation.receipt_sha256 == intent.evaluation_receipt_sha256
  end

  test "actuator refuses DO without BRCE authority even when a perform function is supplied",
       %{counter: counter} do
    intent = matched_intent!()

    assert {:error, refusal} =
             Actuator.actuate(
               intent,
               %{
                 brce?: false,
                 authority_sha256: String.duplicate("a", 64),
                 brce_receipt_sha256: String.duplicate("b", 64),
                 pre_state_sha256: String.duplicate("c", 64),
                 post_state_sha256: String.duplicate("d", 64)
               },
               perform: fn _target, _payload ->
                 Agent.update(counter, &(&1 + 1))
                 {:ok, :bumped}
               end
             )

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.detail =~ "BRCE"
    assert Agent.get(counter, & &1) == 0
  end

  test "actuator refuses missing consequence identities and never runs perform", %{counter: counter} do
    intent = matched_intent!()

    assert {:error, refusal} =
             Actuator.actuate(
               intent,
               %{brce?: true, authority_sha256: String.duplicate("a", 64)},
               perform: fn _, _ ->
                 Agent.update(counter, &(&1 + 1))
                 {:ok, :nope}
               end
             )

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert :brce_receipt_sha256 in refusal.evidence.missing
    assert :pre_state_sha256 in refusal.evidence.missing
    assert :post_state_sha256 in refusal.evidence.missing
    assert Agent.get(counter, & &1) == 0
  end

  test "actuator refuses to run without an admitted perform/2 at the DO boundary" do
    intent = matched_intent!()

    assert {:error, refusal} =
             Actuator.actuate(intent, %{
               brce?: true,
               authority_sha256: String.duplicate("a", 64),
               brce_receipt_sha256: String.duplicate("b", 64),
               pre_state_sha256: String.duplicate("c", 64),
               post_state_sha256: String.duplicate("d", 64)
             })

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.detail =~ "perform"
  end

  test "hook definitions still refuse ambient callbacks; effect belongs only on the actuator side",
       %{counter: counter} do
    assert {:error, [refusal]} =
             KnowledgeHooks.admit([
               %{
                 id: "ambient",
                 name: "Ambient",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: "pipeline://notify-ready",
                 callback: fn -> Agent.update(counter, &(&1 + 1)) end
               }
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert :callback in refusal.evidence.forbidden_keys
    assert Agent.get(counter, & &1) == 0
  end

  defp matched_intent! do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "ready-notify",
                 name: "Ready notify",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: %{kind: :pipeline, target: "pipeline://notify-ready", payload: %{}}
               }
             ])

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan, current: [data: @ready_graph, strategy: :local_rdf])

    assert evaluation.matched?
    evaluation.intent
  end

  defp sha(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
  end
end
