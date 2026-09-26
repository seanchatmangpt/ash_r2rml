# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RFCClosureFalsifierTest do
  @moduledoc """
  Chicago falsifiers for docs/jira/v26.9.16/RFC-CLOSURE.md (A2A-2608 / A2A-2612).

  Every test drives the real `AshR2RML.DfCM.Compiler` over a real admitted profile and
  asserts on the resulting receipts, identities, and typed refusals. No collaborator is
  replaced by a double. Each `describe` block names the RFC falsifier it attacks.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.DfCM.Compiler, as: DfCM

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp profile(overrides \\ %{}) do
    base = %{
      ontology_hash: "ontology:rfc-closure",
      profile_hash: "profile:rfc-closure",
      shacl_hash: "shacl:rfc-closure",
      resources: [
        %{
          iri: "https://example.org/resource/Person",
          class_iri: "https://schema.org/Person",
          shape_iri: "https://example.org/shapes/PersonShape",
          module: "RFCClosure.Person",
          repo_module: "RFCClosure.Repo",
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

  defp compiled(overrides \\ %{}) do
    {:ok, envelope} = DfCM.compile(profile(overrides))
    envelope
  end

  defp witness(envelope, id, overrides \\ %{}) do
    Map.merge(
      %{
        verified?: true,
        session_sha256: envelope.session_identity.sha256,
        receipt_sha256: id,
        observed?: true,
        left_observation_sha256: "left-" <> id,
        right_observation_sha256: "right-" <> id,
        subject_identity_verified?: true
      },
      overrides
    )
  end

  defp fully_witnessed(envelope) do
    envelope
    |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "sparql-sql"))
    |> DfCM.attach_parity_witness(:neo4j_postgres, witness(envelope, "neo4j-postgres"))
  end

  defp authority, do: %{authorized?: true, receipt_sha256: "operator-authority"}

  defp tamper(envelope, field, fun) do
    %{envelope | compilation: Map.update!(envelope.compilation, field, fun)}
  end

  describe "closure 1: projection identity is bound to the admitted semantic source" do
    test "an untouched compilation re-derives its own session identity" do
      envelope = compiled()
      assert {:ok, sha} = DfCM.verify_projection_identity(envelope)
      assert sha == envelope.session_identity.sha256
    end

    test "session identity changes with every admitted-source component" do
      base = compiled().session_identity.sha256

      for override <- [
            %{ontology_hash: "ontology:other"},
            %{profile_hash: "profile:other"},
            %{shacl_hash: "shacl:other"}
          ] do
        refute compiled(override).session_identity.sha256 == base, inspect(override)
      end
    end

    test "session identity binds the manufacturer (compiler module digest)" do
      identity = compiled().session_identity
      assert is_binary(identity.compiler_module_sha256)

      assert identity.compiler_module_sha256 ==
               AshR2RML.SemanticSessionIdentity.module_sha256(AshR2RML.Compiler)

      other_manufacturer =
        identity
        |> Map.from_struct()
        |> Map.drop([:sha256])
        |> Map.put(:compiler_module_sha256, String.duplicate("0", 64))
        |> AshR2RML.SemanticSessionIdentity.new()

      refute other_manufacturer.sha256 == identity.sha256
    end

    test "replay is byte-identical: same source yields same identity and integrity receipt" do
      a = compiled()
      b = compiled()
      assert a.session_identity.sha256 == b.session_identity.sha256
      assert a.integrity_receipt.receipt_sha256 == b.integrity_receipt.receipt_sha256
      assert a.compilation.r2rml == b.compilation.r2rml
    end
  end

  describe "falsifier: modify a generated projection while preserving its claimed identity" do
    for field <- [:ash_source, :ecto_migration, :postgres_ddl, :r2rml, :shacl] do
      test "a single appended byte in #{field} is refused" do
        envelope = compiled() |> tamper(unquote(field), &(&1 <> " "))

        assert {:error, refusal} = DfCM.verify_projection_identity(envelope)
        assert refusal.code == :REFUSED_PROJECTION_DRIFT
        assert [{_name, :bytes_do_not_match_receipt}] = refusal.evidence.drifted
      end
    end

    test "a dropped projection is refused, not treated as absent-and-fine" do
      envelope = compiled() |> tamper(:r2rml, fn _ -> nil end)
      assert {:error, refusal} = DfCM.verify_projection_identity(envelope)
      assert {:r2rml, :missing_projection} in refusal.evidence.drifted
    end

    test "rewriting the projection and its receipt digest together is still caught" do
      envelope = compiled()
      forged_r2rml = envelope.compilation.r2rml <> "\n# forged"
      forged_digest = AshR2RML.Compiler.sha256(forged_r2rml)

      forged =
        %{
          envelope
          | compilation: %{
              envelope.compilation
              | r2rml: forged_r2rml,
                receipt: %{envelope.compilation.receipt | r2rml_sha256: forged_digest}
            }
        }

      assert {:error, refusal} = DfCM.verify_projection_identity(forged)
      assert {:r2rml, :bytes_do_not_match_session_identity} in refusal.evidence.drifted
      assert {:session_identity, :does_not_rederive_from_receipt} in refusal.evidence.drifted
    end

    test "a forged session identity that re-records the forged digest does not re-derive" do
      envelope = compiled()
      forged_r2rml = envelope.compilation.r2rml <> "\n# forged"
      forged_digest = AshR2RML.Compiler.sha256(forged_r2rml)
      metadata = envelope.session_identity.metadata
      hashes = Map.put(metadata.projection_hashes, :r2rml, forged_digest)

      forged_identity = %{
        envelope.session_identity
        | metadata: %{metadata | projection_hashes: hashes}
      }

      forged = %{
        envelope
        | session_identity: forged_identity,
          compilation: %{
            envelope.compilation
            | r2rml: forged_r2rml,
              receipt: %{envelope.compilation.receipt | r2rml_sha256: forged_digest}
          }
      }

      assert {:error, refusal} = DfCM.verify_projection_identity(forged)
      assert refusal.evidence.drifted == [{:session_identity, :does_not_rederive_from_receipt}]
    end

    test "a fully re-sealed forgery is self-consistent but refused against the admitted identity" do
      admitted = compiled()
      forged_r2rml = admitted.compilation.r2rml <> "\n# forged"
      forged_digest = AshR2RML.Compiler.sha256(forged_r2rml)
      metadata = admitted.session_identity.metadata

      resealed_identity =
        admitted.session_identity
        |> Map.from_struct()
        |> Map.drop([:sha256])
        |> Map.put(:metadata, %{
          metadata
          | projection_hashes: Map.put(metadata.projection_hashes, :r2rml, forged_digest)
        })
        |> AshR2RML.SemanticSessionIdentity.new()

      forged = %{
        admitted
        | session_identity: resealed_identity,
          compilation: %{
            admitted.compilation
            | r2rml: forged_r2rml,
              receipt: %{admitted.compilation.receipt | r2rml_sha256: forged_digest}
          }
      }

      # Local self-consistency cannot detect a complete re-seal; the admitted identity can.
      assert {:ok, _} = DfCM.verify_projection_identity(forged)
      assert {:error, refusal} = DfCM.admit_receipt_reuse(admitted, forged)
      assert refusal.code == :REFUSED_SESSION_IDENTITY_MISMATCH

      stale =
        forged
        |> DfCM.attach_parity_witness(:sparql_sql, witness(admitted, "admitted-witness"))
        |> DfCM.authorize_cutover(authority())

      refute DfCM.cutover_ready?(stale)
    end

    test "an environment-bound envelope still verifies, and still refuses drift" do
      bound =
        DfCM.bind_verification_environment(compiled(), %{
          postgres: %{version: "16", fixture_sha256: "fixture"},
          obda: %{engine: :ontop, version: "5.5.0"},
          metadata: %{runner: "local"}
        })

      assert {:ok, sha} = DfCM.verify_projection_identity(bound)
      assert sha == bound.session_identity.sha256

      assert {:error, %{code: :REFUSED_PROJECTION_DRIFT}} =
               bound |> tamper(:shacl, &(&1 <> " ")) |> DfCM.verify_projection_identity()
    end

    test "a staged artifact graph with a drifted projection cannot be published" do
      envelope = compiled()
      c = envelope.compilation
      files = %{"mapping.r2rml.ttl" => c.r2rml, "shapes.shacl.ttl" => c.shacl}
      plan = AshR2RML.Manufacturing.plan(files, envelope.session_identity)
      assert plan.standing == :construct_only
      assert plan.session_sha256 == envelope.session_identity.sha256

      drifted = Map.put(plan.file_hashes, "mapping.r2rml.ttl", AshR2RML.Integrity.Canonical.sha256(c.r2rml <> " "))
      assert {:error, refusal} = AshR2RML.Manufacturing.verify_staged(plan, drifted)
      assert refusal.evidence.mismatched == ["mapping.r2rml.ttl"]

      extra = Map.put(plan.file_hashes, "smuggled.ttl", "x")
      assert {:error, refusal} = AshR2RML.Manufacturing.verify_staged(plan, extra)
      assert refusal.evidence.extra == ["smuggled.ttl"]

      missing = Map.delete(plan.file_hashes, "shapes.shacl.ttl")
      assert {:error, refusal} = AshR2RML.Manufacturing.verify_staged(plan, missing)
      assert refusal.evidence.missing == ["shapes.shacl.ttl"]
    end
  end

  describe "falsifier: cut over without the required parity witness" do
    test "authority alone never makes cutover ready" do
      envelope = compiled() |> DfCM.authorize_cutover(authority())
      refute DfCM.cutover_ready?(envelope)
      assert envelope.compilation.receipt.query_parity != :VERIFIED
    end

    test "the optional Neo4j control witness cannot substitute for SPARQL/SQL parity" do
      # The admitted receipt blocks only on :sparql_sql_behavioral_parity (the Neo4j
      # graph-database surface was retired in 3457767); a neo4j_postgres witness is a
      # control observation and must never stand in for the required SPARQL/SQL witness.
      envelope = compiled()
      assert envelope.compilation.receipt.blocked == [:sparql_sql_behavioral_parity, :cutover_authority]

      control_only =
        envelope
        |> DfCM.attach_parity_witness(:neo4j_postgres, witness(envelope, "neo4j-postgres"))
        |> DfCM.authorize_cutover(authority())

      refute DfCM.cutover_ready?(control_only)
      assert control_only.compilation.receipt.query_parity == :UNKNOWN
      assert :sparql_sql_behavioral_parity in control_only.compilation.receipt.blocked
    end

    test "the required SPARQL/SQL witness plus authority is ready without the optional control" do
      envelope = compiled()

      ready =
        envelope
        |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "sparql-sql"))
        |> DfCM.authorize_cutover(authority())

      assert DfCM.cutover_ready?(ready)
    end

    for {label, override} <- [
          {"unverified", %{verified?: false}},
          {"unobserved", %{observed?: false}},
          {"missing left observation", %{left_observation_sha256: ""}},
          {"missing right observation", %{right_observation_sha256: nil}},
          {"missing receipt id", %{receipt_sha256: ""}}
        ] do
      test "a #{label} witness is refused and grants no parity proof" do
        envelope = compiled()

        attempted =
          envelope
          |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "s", unquote(Macro.escape(override))))
          |> DfCM.attach_parity_witness(:neo4j_postgres, witness(envelope, "n", unquote(Macro.escape(override))))
          |> DfCM.authorize_cutover(authority())

        refute :result_parity_verified in attempted.proof_classes
        refute DfCM.cutover_ready?(attempted)

        assert Enum.count(attempted.compilation.receipt.refusals, &(&1.code == :REFUSED_UNPROVEN_EQUIVALENCE)) == 2
      end
    end

    test "full witnesses plus authority is the only ready path (positive control)" do
      ready = compiled() |> fully_witnessed() |> DfCM.authorize_cutover(authority())
      assert DfCM.cutover_ready?(ready)
    end

    test "duplicate delivery of the same witness is idempotent in the receipt" do
      envelope = compiled()
      once = fully_witnessed(envelope)

      twice =
        once
        |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "sparql-sql"))
        |> DfCM.attach_parity_witness(:neo4j_postgres, witness(envelope, "neo4j-postgres"))

      assert twice.compilation.receipt.verified == once.compilation.receipt.verified
      assert twice.integrity_receipt.receipt_sha256 == once.integrity_receipt.receipt_sha256
    end

    test "witness delivery order does not change the resulting proof classes" do
      envelope = compiled()
      forward = fully_witnessed(envelope)

      reverse =
        envelope
        |> DfCM.attach_parity_witness(:neo4j_postgres, witness(envelope, "neo4j-postgres"))
        |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "sparql-sql"))

      assert Enum.sort(forward.proof_classes) == Enum.sort(reverse.proof_classes)
      assert forward.integrity_receipt.standing == reverse.integrity_receipt.standing
      assert Enum.sort(forward.compilation.receipt.blocked) == Enum.sort(reverse.compilation.receipt.blocked)
    end
  end

  describe "falsifier: runtime/source session identity crosses semantic revisions silently" do
    test "a receipt from revision N is refused for revision N+1" do
      old = compiled()
      new = compiled(%{ontology_hash: "ontology:rfc-closure-v2"})

      refute DfCM.receipt_reusable?(old, new)
      assert {:error, refusal} = DfCM.admit_receipt_reuse(old, new)
      assert refusal.code == :REFUSED_SESSION_IDENTITY_MISMATCH
      assert refusal.evidence.expected_sha256 == old.session_identity.sha256
      assert refusal.evidence.observed_sha256 == new.session_identity.sha256
    end

    test "a stale-revision parity witness is refused on the new revision" do
      old = compiled()
      new = compiled(%{ontology_hash: "ontology:rfc-closure-v2"})

      stale =
        new
        |> DfCM.attach_parity_witness(:sparql_sql, witness(old, "stale-sparql"))
        |> DfCM.attach_parity_witness(:neo4j_postgres, witness(old, "stale-neo4j"))
        |> DfCM.authorize_cutover(authority())

      refute DfCM.cutover_ready?(stale)

      assert Enum.all?(
               Enum.filter(stale.compilation.receipt.refusals, &(&1.code == :REFUSED_UNPROVEN_EQUIVALENCE)),
               &(&1.evidence.observed_session_sha256 == old.session_identity.sha256)
             )
    end

    test "binding a new verification environment revokes previously attached parity" do
      ready = compiled() |> fully_witnessed() |> DfCM.authorize_cutover(authority())
      assert DfCM.cutover_ready?(ready)

      rebound =
        DfCM.bind_verification_environment(ready, %{
          postgres: %{version: "17", fixture_sha256: "fixture-v2"}
        })

      refute DfCM.cutover_ready?(rebound)
      refute rebound.session_identity.sha256 == ready.session_identity.sha256
      assert rebound.compilation.receipt.cutover_authority == :UNAUTHORIZED
      refute :result_parity_verified in rebound.proof_classes

      replayed_old_env = DfCM.attach_parity_witness(rebound, :sparql_sql, witness(ready, "old-env"))
      refute :result_parity_verified in replayed_old_env.proof_classes
    end
  end

  describe "falsifier: receipt feedback mutates canonical mapping state without admission" do
    test "refused and admitted witnesses never touch IR, mapping, projections, or identity" do
      envelope = compiled()

      after_feedback =
        envelope
        |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "x", %{session_sha256: "forged"}))
        |> fully_witnessed()
        |> DfCM.authorize_cutover(authority())

      for field <- [:ir, :mapping_bundle, :ash_source, :ecto_migration, :postgres_ddl, :r2rml, :shacl] do
        assert Map.fetch!(after_feedback.compilation, field) == Map.fetch!(envelope.compilation, field),
               "#{field} changed through receipt feedback"
      end

      assert after_feedback.session_identity == envelope.session_identity
      assert {:ok, _} = DfCM.verify_projection_identity(after_feedback)
    end

    test "machine-experience input is only a candidate: compile-back yields a plan, not a new admitted state" do
      admitted = compiled()

      candidate_profile =
        update_in(profile(), [:resources], fn [person] -> [%{person | table: "people_learned"}] end)

      assert {:ok, candidate} = DfCM.compile(candidate_profile)
      plan = DfCM.incremental_plan(admitted, candidate)

      assert plan.mode == :recompile
      assert :fresh_external_parity in plan.blocked
      assert :fresh_projection_receipt in plan.blocked
      refute DfCM.receipt_reusable?(admitted, candidate)
      assert {:ok, _} = DfCM.verify_projection_identity(admitted)
      assert admitted.compilation.ir.resources |> hd() |> Map.fetch!(:table) == "people"
    end
  end

  describe "falsifier: projection success is treated as execution authority" do
    test "a successful projection is CONSTRUCT-only and unauthorized" do
      envelope = compiled()
      assert envelope.compilation.standing == :constructed_not_actuated
      assert envelope.compilation.receipt.cutover_authority == :UNAUTHORIZED
      refute DfCM.cutover_ready?(envelope)
      refute AshR2RML.Proof.achieved?(envelope.proof_classes, :subject_parity_alive)
      assert {:ok, _} = DfCM.verify_projection_identity(envelope)
    end

    for {label, auth} <- [
          {"unauthorized", %{authorized?: false, receipt_sha256: "a"}},
          {"missing authority receipt", %{authorized?: true}},
          {"empty authority receipt", %{authorized?: true, receipt_sha256: ""}}
        ] do
      test "full parity with #{label} authority is not cutover-ready" do
        envelope = compiled() |> fully_witnessed() |> DfCM.authorize_cutover(unquote(Macro.escape(auth)))
        refute DfCM.cutover_ready?(envelope)
        assert envelope.compilation.receipt.cutover_authority == :UNAUTHORIZED
      end
    end
  end
end
