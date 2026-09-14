defmodule AshR2RML.SemanticSubjectTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{SemanticIR, SemanticSubject}

  test "binds the admitted ontology/profile/SHACL identity into one exact subject" do
    ir = %SemanticIR{
      ontology_hash: "sha256:ontology",
      profile_hash: "sha256:profile",
      shacl_hash: "sha256:shacl"
    }

    assert {:ok, subject} = SemanticSubject.from_ir(ir)
    assert String.starts_with?(subject.digest, "sha256:")
    assert subject == elem(SemanticSubject.from_ir(ir), 1)

    assert SemanticSubject.manufacture_input(subject) == %{
             graph_digest: subject.digest,
             ontology_hash: "sha256:ontology",
             profile_hash: "sha256:profile",
             shacl_hash: "sha256:shacl"
           }
  end

  test "a changed admitted source changes the subject identity" do
    base = %SemanticIR{
      ontology_hash: "o1",
      profile_hash: "p1",
      shacl_hash: "s1"
    }

    assert {:ok, first} = SemanticSubject.from_ir(base)
    assert {:ok, second} = SemanticSubject.from_ir(%{base | profile_hash: "p2"})
    refute first.digest == second.digest
  end

  test "refuses incomplete semantic subjects rather than inventing graph identity" do
    ir = %SemanticIR{ontology_hash: "o", profile_hash: nil, shacl_hash: "s"}

    assert {:error, {:refused_semantic_subject, :profile_hash}} =
             SemanticSubject.from_ir(ir)
  end

  test "projects a resolved material without claiming generated projection identity" do
    ir = %SemanticIR{ontology_hash: "o", profile_hash: "p", shacl_hash: "s"}
    assert {:ok, subject} = SemanticSubject.from_ir(ir)

    material = SemanticSubject.resolved_material(subject)
    assert %{"sha256" => digest} = material["digest"]
    assert material["uri"] == "urn:ash-r2rml:semantic-subject:" <> digest
  end
end
