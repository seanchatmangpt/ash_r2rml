defmodule AshR2RML.Gall.RuntimeFeedbackTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Gall.RuntimeFeedback

  @evidence "sha256:" <> String.duplicate("a", 64)
  @graph "sha256:" <> String.duplicate("b", 64)
  @public "https://example.org/process#"
  @work_order "urn:gall:work-order:xaas:001"
  @receipt "urn:gall:receipt:xaas:001"

  defp mapping do
    [
      %{source_key: "latency_ms", predicate: @public <> "latencyMs"},
      %{source_key: "capability", predicate: @public <> "capability", object: :iri}
    ]
  end

  defp candidate(observation, overrides \\ []) do
    RuntimeFeedback.candidate(observation,
      Keyword.merge(
        [
          work_order_iri: @work_order,
          source_receipt_iri: @receipt,
          source_evidence_digest: @evidence,
          source_graph_digest: @graph,
          subject_iri: "https://example.org/run#1",
          mapping: mapping()
        ],
        overrides
      )
    )
  end

  test "receipt-bound observation becomes candidate then admitted delta" do
    observation = %{
      "latency_ms" => 125,
      "capability" => "https://example.org/capability#repair"
    }

    assert {:ok, candidate} = candidate(observation)
    assert candidate.standing == :candidate
    assert candidate.work_order_iri == @work_order
    assert candidate.source_receipt_iri == @receipt
    assert candidate.source_graph_digest == @graph
    assert String.starts_with?(candidate.candidate_digest, "sha256:")

    assert {:ok, admitted} =
             RuntimeFeedback.admit(candidate, @graph,
               public_namespaces: [@public],
               gates: [
                 fn c ->
                   if length(c.triples) == 2, do: :ok, else: {:error, :shape_violation}
                 end
               ]
             )

    assert admitted.standing == :admitted
    assert admitted.work_order_iri == @work_order
    assert admitted.source_receipt_iri == @receipt
    assert admitted.predecessor_graph_digest == @graph
    assert admitted.new_graph_digest != @graph
    assert String.starts_with?(admitted.admission_receipt_digest, "sha256:")
  end

  test "candidate cannot be applied to a different predecessor graph" do
    assert {:ok, candidate} = candidate(%{"latency_ms" => 125})

    moved = "sha256:" <> String.duplicate("c", 64)

    assert {:error, {:refused_runtime_feedback, {:source_graph_mismatch, @graph, ^moved}}} =
             RuntimeFeedback.admit(candidate, moved, public_namespaces: [@public])
  end

  test "private vocabulary is refused without admitted graph identity" do
    assert {:ok, candidate} =
             candidate(%{"latency_ms" => 125},
               mapping: [
                 %{source_key: "latency_ms", predicate: "https://private.invalid/ns#latency"}
               ]
             )

    assert {:error, {:refused_runtime_feedback, {:nonpublic_vocabulary, _}}} =
             RuntimeFeedback.admit(candidate, @graph, public_namespaces: [@public])
  end

  test "law gate refusal never produces admitted delta" do
    assert {:ok, candidate} = candidate(%{"latency_ms" => 125})

    assert {:error, {:refused_runtime_feedback, {:gate_refused, :too_slow}}} =
             RuntimeFeedback.admit(candidate, @graph,
               public_namespaces: [@public],
               gates: [fn _ -> {:error, :too_slow} end]
             )
  end

  test "work-order and receipt identity are load-bearing in candidate digest" do
    observation = %{"latency_ms" => 125}

    {:ok, first} = candidate(observation)

    {:ok, second} =
      candidate(observation,
        source_receipt_iri: "urn:gall:receipt:xaas:002"
      )

    refute first.candidate_digest == second.candidate_digest
  end
end
