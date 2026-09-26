# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RFCClosureProjectionIdentityBoundTest do
  @moduledoc """
  Regression bound for the RFC-closure drift guard (see bench/projection_identity.exs and
  bench/receipts/projection_identity.md for the recorded numbers).

  The bound is relative, so it holds across machines: re-deriving projection identity must
  cost a small fraction of the compile it guards. A generous absolute ceiling catches an
  accidental re-render or quadratic walk. Real compiler, real profile, wall-clock medians.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.DfCM.Compiler, as: DfCM
  alias AshR2RML.Test.RFCClosure.ConnectedProfile

  # {resource tier, absolute median ceiling in microseconds}. Recorded medians at 1.18.4/OTP 27
  # under load average ~200: 52us @10, 445us @100 (bench/receipts/projection_identity.md).
  # The pre-fix implementation re-read the compiler beam per call (~10.5ms @10, ratio ~0.7)
  # and fails both bounds at tier 10.
  @tiers [{10, 5_000}, {100, 20_000}]
  @runs 15
  @max_ratio 0.05

  defp median_us(fun) do
    fun.()

    samples =
      for _ <- 1..@runs do
        {us, _} = :timer.tc(fun)
        us
      end

    samples |> Enum.sort() |> Enum.at(div(@runs, 2))
  end

  for {tier, ceiling_us} <- @tiers do
    test "verify_projection_identity stays within its regression bound at #{tier} resources" do
      tier = unquote(tier)
      ceiling_us = unquote(ceiling_us)
      profile = ConnectedProfile.profile(tier)
      {:ok, envelope} = DfCM.compile(profile)
      assert {:ok, _} = DfCM.verify_projection_identity(envelope)

      compile_us = median_us(fn -> DfCM.compile(profile) end)
      verify_us = median_us(fn -> DfCM.verify_projection_identity(envelope) end)

      assert verify_us <= ceiling_us,
             "verify median #{verify_us}us exceeds absolute ceiling #{ceiling_us}us at tier #{tier}"

      assert verify_us <= compile_us * @max_ratio,
             "verify median #{verify_us}us exceeds #{@max_ratio} x compile median #{compile_us}us"
    end
  end
end
