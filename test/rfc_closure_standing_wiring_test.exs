# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RFCClosureStandingWiringTest do
  @moduledoc """
  Chicago falsifiers for RFC-CLOSURE.md item 3 ("a changed generated artifact must not
  silently acquire standing") on the standing paths themselves, not only on the guard.

  Every test drives the real `AshR2RML.DfCM.Compiler` over real admitted profiles and
  asserts on the resulting standing, plans and typed refusals. No collaborator is replaced.

  Covers the court findings against PR #39 at f1139bc4: IR and mapping-bundle drift admitted
  by `verify_projection_identity/1` (A6/A7), a forged IR flipping per-resource reuse in
  `incremental_plan/2` (A8), and the guard having no caller on the standing path.
  """

  use ExUnit.Case, async: true

  alias AshR2RML.DfCM.Compiler, as: DfCM
  alias AshR2RML.Test.RFCClosure.ConnectedProfile

  defp witness(envelope, id) do
    %{
      verified?: true,
      session_sha256: envelope.session_identity.sha256,
      receipt_sha256: id,
      observed?: true,
      left_observation_sha256: "left-" <> id,
      right_observation_sha256: "right-" <> id,
      subject_identity_verified?: true
    }
  end

  defp ready(envelope) do
    envelope
    |> DfCM.attach_parity_witness(:sparql_sql, witness(envelope, "sparql-sql"))
    |> DfCM.attach_parity_witness(:neo4j_postgres, witness(envelope, "neo4j-postgres"))
    |> DfCM.authorize_cutover(%{authorized?: true, receipt_sha256: "operator-authority"})
  end

  defp compiled(n \\ 3) do
    {:ok, envelope} = DfCM.compile(ConnectedProfile.profile(n))
    envelope
  end

  defp tamper(envelope, field, fun) do
    %{envelope | compilation: Map.update!(envelope.compilation, field, fun)}
  end

  defp drift_ir(ir) do
    [resource | rest] = ir.resources
    %{ir | resources: [%{resource | table: "evil"} | rest]}
  end

  defp drift_mapping_bundle(bundle) do
    [mapping | rest] = bundle.resources
    %{bundle | resources: rest ++ [mapping, mapping]}
  end

  @drifts [
    {:ash_source, :text},
    {:ecto_migration, :text},
    {:postgres_ddl, :text},
    {:r2rml, :text},
    {:shacl, :text},
    {:ir, :ir},
    {:mapping_bundle, :mapping_bundle}
  ]

  defp drift(envelope, field, :text), do: tamper(envelope, field, &(&1 <> " "))
  defp drift(envelope, :ir, :ir), do: tamper(envelope, :ir, &drift_ir/1)
  defp drift(envelope, :mapping_bundle, :mapping_bundle), do: tamper(envelope, :mapping_bundle, &drift_mapping_bundle/1)

  describe "receipted terms: IR and mapping bundle drift fails closed" do
    test "an IR resource edited in place is refused (court A7)" do
      envelope = compiled() |> tamper(:ir, &drift_ir/1)
      assert {:error, refusal} = DfCM.verify_projection_identity(envelope)
      assert refusal.code == :REFUSED_PROJECTION_DRIFT
      assert refusal.evidence.drifted == [{:ir, :term_does_not_match_receipt}]
    end

    test "a duplicated mapping-bundle resource is refused (court A6)" do
      envelope = compiled() |> tamper(:mapping_bundle, &drift_mapping_bundle/1)
      assert {:error, refusal} = DfCM.verify_projection_identity(envelope)
      assert refusal.evidence.drifted == [{:mapping_bundle, :term_does_not_match_receipt}]
    end

    test "a dropped IR is refused" do
      envelope = compiled() |> tamper(:ir, fn _ -> nil end)
      assert {:error, refusal} = DfCM.verify_projection_identity(envelope)
      assert {:ir, :term_does_not_match_receipt} in refusal.evidence.drifted
    end

    test "rewriting the IR and its receipt digest together is still caught" do
      envelope = compiled()
      forged_ir = drift_ir(envelope.compilation.ir)

      forged = %{
        envelope
        | compilation: %{
            envelope.compilation
            | ir: forged_ir,
              receipt: %{envelope.compilation.receipt | ir_sha256: AshR2RML.Compiler.canonical_sha256(forged_ir)}
          }
      }

      assert {:error, refusal} = DfCM.verify_projection_identity(forged)
      assert {:ir, :term_does_not_match_session_identity} in refusal.evidence.drifted
      assert {:session_identity, :does_not_rederive_from_receipt} in refusal.evidence.drifted
    end

    test "canonical_sha256 is the function that sealed the receipt" do
      envelope = compiled()
      c = envelope.compilation
      assert AshR2RML.Compiler.canonical_sha256(c.ir) == c.receipt.ir_sha256
      assert AshR2RML.Compiler.canonical_sha256(c.mapping_bundle) == c.receipt.mapping_sha256
      assert envelope.session_identity.ir_sha256 == c.receipt.ir_sha256
      assert envelope.session_identity.mapping_sha256 == c.receipt.mapping_sha256
    end
  end

  describe "canonical digest: the memoized walk is the original canonical form" do
    # Reference: the canonical form exactly as the compiler defined it before memoization
    # (structs -> maps, entries sorted by inspect(key), lists in order).
    defp reference_canonical(%_{} = struct), do: struct |> Map.from_struct() |> reference_canonical()

    defp reference_canonical(map) when is_map(map) do
      map
      |> Enum.map(fn {key, value} -> {key, reference_canonical(value)} end)
      |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
    end

    defp reference_canonical(list) when is_list(list), do: Enum.map(list, &reference_canonical/1)
    defp reference_canonical(other), do: other

    defp reference_sha256(term), do: term |> reference_canonical() |> AshR2RML.Compiler.sha256()

    test "IR and mapping-bundle digests equal the reference at several tiers" do
      for n <- [1, 3, 10] do
        c = compiled(n).compilation
        assert AshR2RML.Compiler.canonical_sha256(c.ir) == reference_sha256(c.ir)
        assert AshR2RML.Compiler.canonical_sha256(c.mapping_bundle) == reference_sha256(c.mapping_bundle)
      end
    end

    test "a struct with a smuggled or dropped field is not hidden by the per-module memo" do
      c = compiled().compilation
      [first | rest] = c.ir.resources
      smuggled = %{c.ir | resources: [first | Enum.map(rest, &Map.put(&1, :smuggled, "x"))]}
      dropped = %{c.ir | resources: [first | Enum.map(rest, &Map.delete(&1, :table))]}

      for forged <- [smuggled, dropped] do
        digest = AshR2RML.Compiler.canonical_sha256(forged)
        assert digest == reference_sha256(forged)
        refute digest == c.receipt.ir_sha256
      end
    end

    test "mixed and non-atom keys sort exactly as the reference" do
      term = %{
        "b" => 1,
        :a => [%{{:k, 2} => nil, {:k, 1} => true}],
        1 => %{nil: 1, true: 2, "quoted key": 3, z: 4},
        1.0 => :float
      }

      assert AshR2RML.Compiler.canonical_sha256(term) == reference_sha256(term)
    end
  end

  describe "standing: a drifted envelope never becomes cutover-ready" do
    test "positive control: the untouched envelope with witnesses and authority is ready" do
      assert DfCM.cutover_ready?(ready(compiled()))
    end

    for {field, kind} <- @drifts do
      test "drift in #{field} after full witnesses and authority is not cutover-ready" do
        envelope = ready(compiled())
        assert DfCM.cutover_ready?(envelope)

        drifted = drift(envelope, unquote(field), unquote(kind))

        # The receipt and proof classes alone would still say ready: the guard is what refuses.
        assert AshR2RML.Compiler.cutover_ready?(drifted.compilation.receipt)
        assert AshR2RML.Proof.achieved?(drifted.proof_classes, :subject_parity_alive)
        refute DfCM.cutover_ready?(drifted)
      end
    end
  end

  describe "standing: drifted envelopes cannot reuse receipts" do
    for {field, kind} <- @drifts do
      test "an observed envelope drifted in #{field} with its identity preserved is refused reuse" do
        admitted = compiled()
        observed = drift(compiled(), unquote(field), unquote(kind))
        assert observed.session_identity == admitted.session_identity

        refute DfCM.receipt_reusable?(admitted, observed)
        assert {:error, refusal} = DfCM.admit_receipt_reuse(admitted, observed)
        assert refusal.code == :REFUSED_PROJECTION_DRIFT
      end
    end

    test "a drifted retained admitted envelope is also refused as the reuse source" do
      admitted = compiled() |> drift(:ir, :ir)
      refute DfCM.receipt_reusable?(admitted, compiled())
      assert {:error, %{code: :REFUSED_PROJECTION_DRIFT}} = DfCM.admit_receipt_reuse(admitted, compiled())
    end

    test "positive control: two honest compiles of one source reuse" do
      assert DfCM.receipt_reusable?(compiled(), compiled())
      assert {:ok, :identical} = DfCM.admit_receipt_reuse(compiled(), compiled())
    end
  end

  describe "compile-back: a machine-experience candidate is only a plan" do
    defp candidate_profile do
      update_in(ConnectedProfile.profile(3), [:resources], fn [r | rest] ->
        [%{r | table: r.table <> "_learned"} | rest]
      end)
    end

    test "a forged IR cannot mark a changed resource as reusable (court A8)" do
      admitted = compiled()
      {:ok, candidate} = DfCM.compile(candidate_profile())
      honest = DfCM.incremental_plan(admitted, candidate)
      assert honest.drift_classification == :representation_change
      [changed_class] = honest.changed_resource_classes

      forged = %{admitted | compilation: %{admitted.compilation | ir: candidate.compilation.ir}}
      assert {:error, %{code: :REFUSED_PROJECTION_DRIFT}} = DfCM.verify_projection_identity(forged)

      plan = DfCM.incremental_plan(forged, candidate)
      assert plan.mode == :recompile
      assert plan.reusable_resource_classes == []
      assert changed_class in plan.changed_resource_classes
      assert plan.drift_classification == :ambiguous
      assert :projection_identity_drift in plan.blocked
    end

    test "a candidate that claims the admitted identity is refused reuse and stays a plan" do
      admitted = compiled()
      {:ok, candidate} = DfCM.compile(candidate_profile())
      impostor = %{candidate | session_identity: admitted.session_identity}

      refute DfCM.receipt_reusable?(admitted, impostor)
      assert {:error, %{code: :REFUSED_PROJECTION_DRIFT}} = DfCM.admit_receipt_reuse(admitted, impostor)

      plan = DfCM.incremental_plan(admitted, impostor)
      assert plan.mode == :recompile
      assert plan.reusable_resource_classes == []
      assert :projection_identity_drift in plan.blocked

      refute DfCM.cutover_ready?(ready(impostor))
      assert {:ok, _} = DfCM.verify_projection_identity(admitted)
    end

    test "positive control: an honest candidate plan reuses the unchanged resources" do
      admitted = compiled()
      {:ok, candidate} = DfCM.compile(candidate_profile())
      plan = DfCM.incremental_plan(admitted, candidate)
      assert plan.mode == :recompile
      assert length(plan.changed_resource_classes) == 1
      assert length(plan.reusable_resource_classes) == 2
      refute :projection_identity_drift in plan.blocked
    end
  end
end
