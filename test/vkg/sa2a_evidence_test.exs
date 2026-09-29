defmodule AshR2RML.VKG.SA2AEvidenceTest do
  use ExUnit.Case, async: true

  alias AshR2RML.VKG.{SA2AEvidence, SourceIdentity}

  defp source do
    {:ok, source} =
      SourceIdentity.new(%{
        id: "customer",
        uri: "urn:source:customer",
        graph: "urn:graph:customer",
        subject_template: "https://example.org/customer/{id}",
        version: "1"
      })

    source
  end

  test "projects exact VKG source into authority-free portable evidence" do
    assert {:ok, envelope} =
             SA2AEvidence.from_source(source(), %{
               subject: "urn:customer:42",
               graph_digest: String.duplicate("a", 64),
               replay_identity: "replay:customer:42"
             })

    assert envelope["authority"] == "NONE"
    assert envelope["consequence"] == "EVIDENCE_ONLY"
    assert envelope["canonicalization"] == "RDFC-1.0"
    assert envelope["source"]["digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert envelope["envelopeDigest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert :ok = SA2AEvidence.verify(envelope)
  end

  test "authority smuggling is refused" do
    {:ok, envelope} = SA2AEvidence.from_source(source())
    assert {:error, refusal} = SA2AEvidence.verify(%{envelope | "authority" => "DO"})
    assert refusal.code == :REFUSED_VKG_SOURCE_IDENTITY
  end

  test "envelope mutation invalidates replay digest" do
    {:ok, envelope} = SA2AEvidence.from_source(source())
    assert {:error, _} = SA2AEvidence.verify(%{envelope | "subject" => "urn:other"})
  end
end
