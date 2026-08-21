# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ProductionAdmissionTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Production

  @subject String.duplicate("1", 64)

  test "production standing is partial when runtime evidence is absent" do
    admission = Production.admit(Production.default_profile(), @subject, [])

    assert admission.status == :PARTIAL_ALIVE
    assert admission.standing == :technical_production_evidence_incomplete
    assert Enum.sort(admission.missing) == Enum.sort(Production.default_profile().required_evidence)
    refute Production.operational_ready?(admission)
  end

  test "all exact-subject evidence promotes technical standing without granting DO" do
    profile = Production.default_profile()

    evidence =
      Enum.map(profile.required_evidence, fn kind ->
        %Production.Evidence{
          kind: kind,
          status: :VERIFIED,
          subject_sha256: @subject,
          receipt_sha256: receipt_for(kind),
          environment_sha256: String.duplicate("e", 64)
        }
      end)

    admission = Production.admit(profile, @subject, evidence)

    assert admission.status == :ALIVE
    assert admission.missing == []
    assert Production.operational_ready?(admission)

    assert {:error, %Production.Refusal{code: :REFUSED_DO_OUTSIDE_BRCE}} =
             Production.authorize_do(admission, %{})
  end

  test "evidence for a different subject cannot be rebound by prose" do
    [kind | _] = Production.default_profile().required_evidence

    evidence = [
      %Production.Evidence{
        kind: kind,
        status: :VERIFIED,
        subject_sha256: String.duplicate("2", 64),
        receipt_sha256: receipt_for(kind)
      }
    ]

    admission = Production.admit(Production.default_profile(), @subject, evidence)

    assert admission.status == :PARTIAL_ALIVE
    assert Enum.any?(admission.refused, &(&1.code == :REFUSED_EVIDENCE_SUBJECT_MISMATCH))
  end

  test "BRCE DO receipt binds authority, consequence and replay identities" do
    profile = Production.default_profile()

    evidence =
      Enum.map(profile.required_evidence, fn kind ->
        %Production.Evidence{
          kind: kind,
          status: :VERIFIED,
          subject_sha256: @subject,
          receipt_sha256: receipt_for(kind)
        }
      end)

    admission = Production.admit(profile, @subject, evidence)

    authority = %{
      brce?: true,
      authority_sha256: String.duplicate("a", 64),
      pre_state_sha256: String.duplicate("b", 64),
      post_state_sha256: String.duplicate("c", 64),
      replay_plan_sha256: String.duplicate("d", 64),
      brce_receipt_sha256: String.duplicate("f", 64)
    }

    assert {:ok, receipt} = Production.authorize_do(admission, authority)
    assert receipt.subject_sha256 == @subject
    assert receipt.production_receipt_sha256 == admission.receipt_sha256
    assert is_binary(receipt.receipt_sha256)
  end

  test "quality profile refuses relaxed non-negotiable bounds" do
    profile = Production.default_profile()
    weakened = %{profile | objectives: Map.put(profile.objectives, :p99_cold_path_ms, 750)}

    admission = Production.admit(weakened, @subject, [])

    assert admission.status == :BLOCKED
    assert Enum.any?(admission.refused, &(&1.subject == :p99_cold_path_ms))
  end

  defp receipt_for(kind) do
    :crypto.hash(:sha256, Atom.to_string(kind)) |> Base.encode16(case: :lower)
  end
end
