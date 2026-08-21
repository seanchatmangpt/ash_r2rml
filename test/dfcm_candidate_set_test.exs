# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCM.CandidateSetTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DfCM.CandidateSet
  alias AshR2RML.SemanticIR.Relationship

  defp many_relationship(overrides \\ %{}) do
    base = %Relationship{
      name: :members,
      predicate_iri: "https://example.test/member",
      source_class: "https://example.test/Group",
      target_class: "https://example.test/Person",
      cardinality: :many,
      min_count: 0,
      max_count: nil
    }

    struct!(base, overrides)
  end

  defp one_relationship(overrides \\ %{}) do
    base = %Relationship{
      name: :owner,
      predicate_iri: "https://example.test/owner",
      source_class: "https://example.test/Asset",
      target_class: "https://example.test/Person",
      cardinality: :one,
      min_count: 1,
      max_count: 1
    }

    struct!(base, overrides)
  end

  test "narrows to a canonical reversible subset without selecting" do
    assert {:ok, narrowed} =
             CandidateSet.narrow(many_relationship(), [
               "association_resource",
               :join_table,
               :association_resource
             ])

    assert narrowed.storage_strategy == nil
    assert narrowed.storage_candidates == [:join_table, :association_resource]
  end

  test "narrowing is deterministic under candidate input ordering" do
    relationship = many_relationship()

    assert CandidateSet.equivalent?(
             relationship,
             [:association_resource, :join_table],
             ["join_table", "association_resource"]
           )

    assert {:ok, first} =
             CandidateSet.narrow(relationship, [:association_resource, :join_table])

    assert {:ok, replay} =
             CandidateSet.narrow(relationship, ["join_table", "association_resource"])

    assert first == replay
  end

  test "explicit selection must come from the admitted subset" do
    assert {:error, refusal} =
             CandidateSet.select(
               many_relationship(),
               [:join_table, :association_resource],
               :foreign_key
             )

    assert refusal.code == :REFUSED_AMBIGUOUS_RELATIONSHIP
  end

  test "selected implemented strategy remains selected after narrowing" do
    relationship =
      many_relationship(%{
        storage_strategy: :join_table,
        join_table: "group_members",
        source_key: :id,
        destination_key: :id,
        source_join_column: "group_id",
        destination_join_column: "person_id"
      })

    assert {:ok, selected} =
             CandidateSet.select(
               %{relationship | storage_strategy: nil},
               [:join_table, :association_resource],
               "join_table"
             )

    assert selected.storage_strategy == :join_table
    assert selected.storage_candidates == [:join_table, :association_resource]
  end

  test "unimplemented candidate remains a typed refusal rather than silently falling back" do
    assert {:error, refusal} =
             CandidateSet.select(
               many_relationship(),
               [:join_table, :jsonb],
               :jsonb
             )

    assert refusal.code == :REFUSED_PROJECTION_NOT_IMPLEMENTED
  end

  test "cardinality falsifier rejects many-only candidate for to-one relationship" do
    assert {:error, refusal} =
             CandidateSet.narrow(one_relationship(), [:foreign_key, :jsonb])

    assert refusal.code == :REFUSED_CARDINALITY_STORAGE_MISMATCH
  end

  test "unknown candidate is refused with no ambient fallback" do
    assert {:error, refusal} = CandidateSet.narrow(many_relationship(), ["magic_table"])
    assert refusal.code == :REFUSED_AMBIGUOUS_RELATIONSHIP
  end

  test "empty closed candidate set is refused" do
    assert {:error, refusal} = CandidateSet.narrow(many_relationship(), [])
    assert refusal.code == :REFUSED_AMBIGUOUS_RELATIONSHIP
  end

  test "a preselected strategy cannot survive admission that rules it out" do
    assert {:error, refusal} =
             CandidateSet.narrow(
               many_relationship(%{storage_strategy: :foreign_key}),
               [:join_table, :association_resource]
             )

    assert refusal.code == :REFUSED_AMBIGUOUS_RELATIONSHIP
  end
end
