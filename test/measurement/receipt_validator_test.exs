# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Measurement.ReceiptValidatorTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Measurement.ReceiptValidator

  @valid """
  **Execution Timestamp**: `2026-08-21T16:54:03-07:00`
  **Exit Status**: `0`
  Excluding tags: []
  202 tests, 0 failures
  **Total Skipped/Excluded**: 0
  """

  test "measures execution outcome without manufacturing exclusions" do
    assert {:ok, measurement} = ReceiptValidator.validate(@valid)
    assert measurement.tests == 202
    assert measurement.failures == 0
    assert measurement.excluded_tags == []
    refute measurement.selection_exclusions?
  end

  test "refuses a zero-exclusions claim when selection policy excluded tags" do
    receipt = String.replace(@valid, "Excluding tags: []", "Excluding tags: [:slow, :apoc]")

    assert {:error, :receipt_contradictory_exclusions, evidence} =
             ReceiptValidator.validate(receipt)

    assert evidence.claimed_excluded == 0
    assert evidence.observed_excluded_tags == [:slow, :apoc]
  end

  test "preserves UNKNOWN exclusion cardinality when only tag policy is observed" do
    receipt =
      @valid
      |> String.replace("Excluding tags: []", "Excluding tags: [:slow]")
      |> String.replace("**Total Skipped/Excluded**: 0", "")

    assert {:ok, measurement} = ReceiptValidator.validate(receipt)
    assert measurement.excluded_tags == [:slow]
    assert measurement.selection_exclusions?
  end

  test "refuses stale evidence against an explicit freshness bound" do
    now = ~U[2026-08-22 00:54:04Z]

    assert {:error, :receipt_stale, evidence} =
             ReceiptValidator.validate(@valid, now: now, max_age_seconds: 3600)

    assert evidence.age_seconds > evidence.max_age_seconds
  end

  test "accepts evidence inside an explicit freshness bound" do
    now = ~U[2026-08-21 23:55:00Z]

    assert {:ok, _measurement} =
             ReceiptValidator.validate(@valid, now: now, max_age_seconds: 3600)
  end
end
