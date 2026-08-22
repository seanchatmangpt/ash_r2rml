# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCM.StorageProbeTest do
  use ExUnit.Case, async: true

  alias AshR2RML.DfCM.StorageProbe
  alias AshR2RML.SemanticIR.Relationship

  defp relationship do
    %Relationship{
      name: :members,
      predicate_iri: "https://www.w3.org/ns/org#hasMember",
      source_class: "https://www.w3.org/ns/org#Organization",
      target_class: "http://xmlns.com/foaf/0.1/Person",
      min_count: 0,
      max_count: nil,
      cardinality: :many,
      provenance: %{shape: "https://example.test/shapes/OrganizationShape"}
    }
  end

  test "EXPLORE preserves every lawful candidate including currently unimplemented projections" do
    assert {:ok, plans} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")

    assert Enum.map(plans, & &1.candidate) == [
             :foreign_key,
             :join_table,
             :association_resource,
             :array,
             :jsonb,
             :computed_projection
           ]

    assert length(Enum.uniq(Enum.map(plans, & &1.id))) == 6
  end

  test "plan identities replay deterministically for the same exact subject" do
    assert {:ok, first} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")
    assert {:ok, second} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")

    assert Enum.map(first, & &1.id) == Enum.map(second, & &1.id)
  end

  test "probe-scoped ALIVE requires exact binding, all checks, execution, and a receipt" do
    assert {:ok, [foreign_key | _]} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")

    checks = Map.new(foreign_key.required_checks, &{&1, true})

    assert {:ok, result} =
             StorageProbe.observe(foreign_key, %{
               plan_id: foreign_key.id,
               subject_sha256: foreign_key.subject_sha256,
               candidate: foreign_key.candidate,
               checks: checks,
               executed?: true,
               receipt_sha256: "probe-receipt:sha256:123"
             })

    assert result.standing == :ALIVE
    assert result.receipt_sha256 == "probe-receipt:sha256:123"
    assert result.blocked == []
  end

  test "passing checks without observed execution remains PARTIAL_ALIVE" do
    assert {:ok, [foreign_key | _]} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")
    checks = Map.new(foreign_key.required_checks, &{&1, true})

    assert {:ok, result} =
             StorageProbe.observe(foreign_key, %{
               plan_id: foreign_key.id,
               subject_sha256: foreign_key.subject_sha256,
               candidate: foreign_key.candidate,
               checks: checks
             })

    assert result.standing == :PARTIAL_ALIVE
    assert result.blocked == [:observed_execution_receipt]
  end

  test "stale or cross-subject observations are refused" do
    assert {:ok, [foreign_key | _]} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")
    checks = Map.new(foreign_key.required_checks, &{&1, true})

    assert {:error, refusal} =
             StorageProbe.observe(foreign_key, %{
               plan_id: foreign_key.id,
               subject_sha256: "semantic-ir:sha256:stale",
               candidate: foreign_key.candidate,
               checks: checks,
               executed?: true,
               receipt_sha256: "probe-receipt:sha256:123"
             })

    assert refusal.code == :REFUSED_STORAGE_PROBE_SUBJECT_MISMATCH
  end

  test "explicit falsifiers dominate otherwise passing observations" do
    assert {:ok, plans} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")
    join_table = Enum.find(plans, &(&1.candidate == :join_table))

    checks =
      join_table.required_checks
      |> Map.new(&{&1, true})
      |> Map.put(:identity_collision, true)

    assert {:error, refusal} =
             StorageProbe.observe(join_table, %{
               plan_id: join_table.id,
               subject_sha256: join_table.subject_sha256,
               candidate: join_table.candidate,
               checks: checks,
               executed?: true,
               receipt_sha256: "probe-receipt:sha256:bad"
             })

    assert refusal.code == :REFUSED_STORAGE_PROBE_FAILED
  end

  test "multiple experimentally ALIVE alternatives remain admitted rather than auto-selected" do
    assert {:ok, plans} = StorageProbe.plans(relationship(), "semantic-ir:sha256:abc")

    results =
      for candidate <- [:foreign_key, :join_table] do
        plan = Enum.find(plans, &(&1.candidate == candidate))
        checks = Map.new(plan.required_checks, &{&1, true})

        assert {:ok, result} =
                 StorageProbe.observe(plan, %{
                   plan_id: plan.id,
                   subject_sha256: plan.subject_sha256,
                   candidate: plan.candidate,
                   checks: checks,
                   executed?: true,
                   receipt_sha256: "probe-receipt:#{candidate}"
                 })

        result
      end

    assert StorageProbe.admitted_candidates(results) == [:foreign_key, :join_table]
  end
end
