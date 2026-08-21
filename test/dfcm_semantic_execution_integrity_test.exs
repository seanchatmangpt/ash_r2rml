# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.DfCMSemanticExecutionIntegrityTest do
  use ExUnit.Case, async: true

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp profile(overrides \\ %{}) do
    base = %{
      ontology_hash: "ontology:integrity",
      profile_hash: "profile:integrity",
      shacl_hash: "shacl:integrity",
      resources: [
        %{
          iri: "https://example.org/resource/Person",
          class_iri: "https://schema.org/Person",
          shape_iri: "https://example.org/shapes/PersonShape",
          module: "Integrity.Person",
          repo_module: "Integrity.Repo",
          table: "people",
          subject_template: "https://example.org/people/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://example.org/ontology/id",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %{
              name: :name,
              column: "name",
              predicate_iri: "http://xmlns.com/foaf/0.1/name",
              datatype_iri: @xsd_string,
              ash_type: :string,
              postgres_type: "TEXT",
              min_count: 0,
              max_count: 1,
              nullable: true
            }
          ]
        }
      ]
    }

    Map.merge(base, overrides)
  end

  test "exact semantic-session identity governs receipt reuse" do
    assert {:ok, first} = AshR2RML.DfCM.Compiler.compile(profile())
    assert {:ok, second} = AshR2RML.DfCM.Compiler.compile(profile())

    assert first.session_identity.sha256 == second.session_identity.sha256
    assert AshR2RML.DfCM.Compiler.receipt_reusable?(first, second)
    assert {:ok, :identical} = AshR2RML.DfCM.Compiler.admit_receipt_reuse(first, second)
    assert first.integrity_receipt.standing == :projections_deterministic
    assert :mapping_admitted in first.proof_classes
    assert :projections_deterministic in first.proof_classes
  end

  test "verification environment identity is explicit and invalidates prior external proof" do
    assert {:ok, compilation} = AshR2RML.DfCM.Compiler.compile(profile())

    bound =
      AshR2RML.DfCM.Compiler.bind_verification_environment(compilation, %{
        postgres: %{version: "16", fixture_sha256: "fixture"},
        obda: %{engine: :ontop, version: "5.5.0", image_digest: "sha256:example"}
      })

    refute bound.session_identity.sha256 == compilation.session_identity.sha256
    assert bound.session_identity.postgres.version == "16"
    assert bound.session_identity.obda.version == "5.5.0"
    assert bound.compilation.receipt.query_parity == :UNKNOWN
    refute :result_parity_verified in bound.proof_classes
  end

  test "semantic drift distinguishes representation, identity, destructive and additive changes" do
    assert {:ok, compilation} = AshR2RML.DfCM.Compiler.compile(profile())
    ir = compilation.compilation.ir
    [person] = ir.resources

    representation = %{ir | resources: [%{person | table: "people_v2"}]}
    assert AshR2RML.SemanticDrift.compare(ir, representation).classification == :representation_change

    identity = %{ir | resources: [%{person | subject_template: "https://example.org/person/{id}"}]}
    assert AshR2RML.SemanticDrift.compare(ir, identity).classification == :identity_affecting

    [id, name] = person.attributes
    destructive = %{ir | resources: [%{person | attributes: [id]}]}
    assert AshR2RML.SemanticDrift.compare(ir, destructive).classification == :destructive

    optional = %{name | name: :nickname, column: "nickname", predicate_iri: "https://schema.org/alternateName"}
    additive = %{ir | resources: [%{person | attributes: person.attributes ++ [optional]}]}
    assert AshR2RML.SemanticDrift.compare(ir, additive).classification == :additive
  end

  test "content-addressed incremental planning reuses only exact or unchanged subjects" do
    assert {:ok, old} = AshR2RML.DfCM.Compiler.compile(profile())
    assert {:ok, exact} = AshR2RML.DfCM.Compiler.compile(profile())

    exact_plan = AshR2RML.DfCM.Compiler.incremental_plan(old, exact)
    assert exact_plan.mode == :reuse_exact_receipt
    assert exact_plan.changed_resource_classes == []
    assert exact_plan.reusable_resource_classes == ["https://schema.org/Person"]

    changed_profile =
      update_in(profile(), [:resources], fn [person] ->
        [%{person | table: "people_v2"}]
      end)

    assert {:ok, changed} = AshR2RML.DfCM.Compiler.compile(changed_profile)
    changed_plan = AshR2RML.DfCM.Compiler.incremental_plan(old, changed)
    assert changed_plan.mode == :recompile
    assert changed_plan.drift_classification == :representation_change
    assert changed_plan.changed_resource_classes == ["https://schema.org/Person"]
    assert :fresh_external_parity in changed_plan.blocked
  end

  test "resource and input bounds fail closed before semantic manufacture" do
    bounded = Map.put(profile(), :bounds, %{max_resources: 0})
    assert {:error, refusal} = AshR2RML.DfCM.Compiler.compile(bounded)
    assert refusal.code == :REFUSED_RESOURCE_BOUND

    assert {:error, input_refusal} = AshR2RML.Bounds.admit_input("too large", max_input_bytes: 2)
    assert input_refusal.code == :REFUSED_RESOURCE_BOUND
  end

  test "strict DfCM parity witnesses are bound to the exact session identity" do
    assert {:ok, compilation} = AshR2RML.DfCM.Compiler.compile(profile())

    refused =
      AshR2RML.DfCM.Compiler.attach_parity_witness(compilation, :sparql_sql, %{
        verified?: true,
        session_sha256: "different-session",
        receipt_sha256: "wrong-session-receipt",
        observed?: true,
        left_observation_sha256: "left-wrong",
        right_observation_sha256: "right-wrong",
        subject_identity_verified?: true
      })

    refute :result_parity_verified in refused.proof_classes
    assert Enum.any?(refused.compilation.receipt.refusals, &(&1.code == :REFUSED_UNPROVEN_EQUIVALENCE))

    session = compilation.session_identity.sha256

    admitted =
      compilation
      |> AshR2RML.DfCM.Compiler.attach_parity_witness(:sparql_sql, %{
        verified?: true,
        session_sha256: session,
        receipt_sha256: "sparql-sql",
        observed?: true,
        left_observation_sha256: "ontop-observation",
        right_observation_sha256: "postgres-observation",
        subject_identity_verified?: true
      })
      |> AshR2RML.DfCM.Compiler.attach_parity_witness(:neo4j_postgres, %{
        verified?: true,
        session_sha256: session,
        receipt_sha256: "neo4j-postgres",
        observed?: true,
        left_observation_sha256: "neo4j-observation",
        right_observation_sha256: "postgres-observation",
        subject_identity_verified?: true
      })
      |> AshR2RML.DfCM.Compiler.authorize_cutover(%{
        authorized?: true,
        receipt_sha256: "operator-authority"
      })

    assert AshR2RML.Proof.achieved?(admitted.proof_classes, :subject_parity_alive)
    assert AshR2RML.DfCM.Compiler.cutover_ready?(admitted)
  end

  test "parity receipts can carry the exact semantic-session identity" do
    receipt =
      AshR2RML.Parity.compare(
        :sparql_sql,
        :person,
        [%{id: "1"}],
        [%{"id" => "1"}],
        %{
          session_sha256: "session-1",
          observed?: true,
          left_observation_sha256: "left-observation",
          right_observation_sha256: "right-observation"
        }
      )

    assert receipt.verified?
    assert receipt.observed?
    assert receipt.session_sha256 == "session-1"
    assert is_binary(receipt.receipt_sha256)
  end

  test "manufacturing plans require an exact staged artifact graph" do
    identity = AshR2RML.SemanticSessionIdentity.new(%{ir_sha256: "ir", mapping_sha256: "mapping"})
    plan = AshR2RML.Manufacturing.plan(%{"a.txt" => "alpha", "b.txt" => "beta"}, identity)

    assert plan.session_sha256 == identity.sha256
    assert plan.protocol == [
             :write_isolated_stage,
             :sync_stage_or_equivalent,
             :verify_exact_file_hashes,
             :atomic_publish,
             :persist_verification_receipt
           ]

    assert {:ok, receipt} = AshR2RML.Manufacturing.verify_staged(plan, plan.file_hashes)
    assert receipt.verified?
    assert receipt.manifest_sha256 == plan.manifest_sha256

    broken = Map.put(plan.file_hashes, "a.txt", "not-the-admitted-hash")
    assert {:error, refusal} = AshR2RML.Manufacturing.verify_staged(plan, broken)
    assert refusal.code == :REFUSED_MANUFACTURING_INCOMPLETE
  end

  test "semantic absence states remain distinct" do
    values = [
      AshR2RML.SemanticValue.null(),
      AshR2RML.SemanticValue.unbound(),
      AshR2RML.SemanticValue.not_asserted(),
      AshR2RML.SemanticValue.unknown(:open_world),
      AshR2RML.SemanticValue.not_projected(:dfcm),
      AshR2RML.SemanticValue.unsupported(:datatype),
      AshR2RML.SemanticValue.refused(:policy)
    ]

    assert values |> Enum.map(&AshR2RML.SemanticValue.kind/1) |> Enum.uniq() |> length() == 7
  end

  test "OBDA capability admission separates standards validity from engine execution" do
    assert {:ok, receipt} =
             AshR2RML.OBDA.Capabilities.admit(:ontop, "5.5.0", [
               :table_name,
               :reference_object_map,
               :join_condition
             ])

    assert receipt.standard_valid?
    assert receipt.engine_supported?
    refute receipt.executed?
    assert AshR2RML.OBDA.Capabilities.mark_executed(receipt).executed?

    assert {:error, refusal} = AshR2RML.OBDA.Capabilities.admit(:unknown_engine, "1", [:join_condition])
    assert refusal.code == :REFUSED_OBDA_CAPABILITY
  end

  test "OBDA execution is bounded and raw output is excluded by default" do
    args = [mapping_path: "mapping.ttl", query_path: "query.rq", timeout_ms: 100]

    runner = fn "ontop", _argv, [] -> {"id,name\n1,Alice\n", 0} end
    assert {:ok, observation} = AshR2RML.OBDA.Ontop.query(args, runner)
    assert observation.raw_output == nil
    assert observation.output_bytes > 0
    assert observation.row_count == 1
    assert is_binary(observation.output_sha256)
    assert is_binary(observation.observation_sha256)
    assert observation.capability_receipt.executed?

    assert {:error, bounded} =
             AshR2RML.OBDA.Ontop.query(Keyword.put(args, :max_output_bytes, 2), runner)

    assert bounded.status == :BLOCKED
    assert bounded.raw_output == nil
    assert bounded.refusal.code == :REFUSED_RESOURCE_BOUND

    slow = fn "ontop", _argv, [] ->
      Process.sleep(30)
      {"id\n1\n", 0}
    end

    assert {:error, timeout} =
             AshR2RML.OBDA.Ontop.query(Keyword.put(args, :timeout_ms, 1), slow)

    assert timeout.status == :BLOCKED
    assert timeout.refusal.code == :REFUSED_RESOURCE_BOUND
  end
end