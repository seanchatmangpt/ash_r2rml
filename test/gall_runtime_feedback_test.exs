defmodule AshR2RML.Gall.RuntimeFeedbackTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Gall.RuntimeFeedback

  @evidence "sha256:" <> String.duplicate("a", 64)
  @graph "sha256:" <> String.duplicate("b", 64)
  @public "https://example.org/process#"

  defp mapping do
    [
      %{source_key: "latency_ms", predicate: @public <> "latencyMs"},
      %{source_key: "capability", predicate: @public <> "capability", object: :iri}
    ]
  end

  test "observation becomes candidate first, then admitted delta with new graph identity" do
    observation = %{
      "latency_ms" => 125,
      "capability" => "https://example.org/capability#repair"
    }

    assert {:ok, candidate} =
             RuntimeFeedback.candidate(observation,
               source_evidence_digest: @evidence,
               subject_iri: "https://example.org/run#1",
               mapping: mapping()
             )

    assert candidate.standing == :candidate
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
    assert admitted.predecessor_graph_digest == @graph
    assert admitted.new_graph_digest != @graph
    assert String.starts_with?(admitted.admission_receipt_digest, "sha256:")
  end

  test "private vocabulary is refused without admitted graph identity" do
    assert {:ok, candidate} =
             RuntimeFeedback.candidate(%{"latency_ms" => 125},
               source_evidence_digest: @evidence,
               subject_iri: "https://example.org/run#1",
               mapping: [
                 %{source_key: "latency_ms", predicate: "https://private.invalid/ns#latency"}
               ]
             )

    assert {:error, {:refused_runtime_feedback, {:nonpublic_vocabulary, _}}} =
             RuntimeFeedback.admit(candidate, @graph,
               public_namespaces: [@public]
             )
  end

  test "law gate refusal never produces admitted delta" do
    assert {:ok, candidate} =
             RuntimeFeedback.candidate(%{"latency_ms" => 125},
               source_evidence_digest: @evidence,
               subject_iri: "https://example.org/run#1",
               mapping: mapping()
             )

    assert {:error, {:refused_runtime_feedback, {:gate_refused, :too_slow}}} =
             RuntimeFeedback.admit(candidate, @graph,
               public_namespaces: [@public],
               gates: [fn _ -> {:error, :too_slow} end]
             )
  end

  test "mapping identity is load-bearing" do
    observation = %{"latency_ms" => 125}

    {:ok, first} =
      RuntimeFeedback.candidate(observation,
        source_evidence_digest: @evidence,
        subject_iri: "https://example.org/run#1",
        mapping: [%{source_key: "latency_ms", predicate: @public <> "latencyMs"}]
      )

    {:ok, second} =
      RuntimeFeedback.candidate(observation,
        source_evidence_digest: @evidence,
        subject_iri: "https://example.org/run#1",
        mapping: [%{source_key: "latency_ms", predicate: @public <> "observedLatencyMs"}]
      )

    refute first.mapping_digest == second.mapping_digest
    refute first.candidate_digest == second.candidate_digest
  end
  test "admitted delta emits exact-head machine-readable receipt without authority" do
    {:ok, candidate} =
      RuntimeFeedback.candidate(%{"latency_ms" => 125},
        source_evidence_digest: @evidence,
        subject_iri: "https://example.org/run#receipt",
        mapping: [%{source_key: "latency_ms", predicate: @public <> "latencyMs"}]
      )

    {:ok, admitted} =
      RuntimeFeedback.admit(candidate, @graph,
        public_namespaces: [@public],
        gates: [fn _ -> :ok end]
      )

    producer_sha = String.duplicate("c", 40)
    assert {:ok, receipt} = RuntimeFeedback.receipt(admitted, producer_sha)

    assert receipt["schema"] == "gall.runtime-feedback-receipt/1"
    assert receipt["producer_sha"] == producer_sha
    assert receipt["source_evidence_digest"] == @evidence
    assert receipt["new_graph_digest"] == admitted.new_graph_digest
    assert receipt["result"] == "ADMITTED_DELTA"
    assert receipt["authority"] == "NONE"
    assert String.starts_with?(receipt["receipt_digest"], "sha256:")

    assert {:error, {:producer_sha, :invalid_git_sha}} =
             RuntimeFeedback.receipt(admitted, "main")
  end

  test "malformed sha256 evidence is typed-refused" do
    assert {:error, {:source_evidence_digest, :invalid_digest}} =
             RuntimeFeedback.candidate(%{"latency_ms" => 125},
               source_evidence_digest: "sha256:" <> String.duplicate("z", 64),
               subject_iri: "https://example.org/run#bad-digest",
               mapping: mapping()
             )
  end

end
