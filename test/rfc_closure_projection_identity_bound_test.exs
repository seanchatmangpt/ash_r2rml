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

  # {resource tier, absolute median ceiling in microseconds}.
  #
  # The guard re-derives the five text projections, the session identity, and (since the
  # court finding against f1139bc4) the canonical IR and mapping-bundle digests, so its floor
  # is a canonical walk plus SHA-256 over roughly the bytes the compile sealed. Recorded
  # medians are in bench/receipts/projection_identity.md. Regressions these bounds kill:
  #   - re-reading the compiler beam per call: ~10.5 ms @10, ratio ~0.7 (fails both @10);
  #   - the unmemoized canonical walk (inspect/1 per map key): ~43-50 ms @100 (fails the
  #     20 ms ceiling @100).
  @tiers [{10, 5_000}, {100, 20_000}]
  @runs 15
  @max_ratio 0.2
  # Wall-clock medians on a shared host are noisy; a real regression is deterministic and
  # fails every attempt, so the bound is asserted on the best of a few attempts, each
  # interleaving compile and verify samples so both see the same load.
  @attempts 3

  defp medians(profile, envelope) do
    DfCM.compile(profile)
    DfCM.verify_projection_identity(envelope)

    {compile, verify} =
      for _ <- 1..@runs do
        {c, _} = :timer.tc(fn -> DfCM.compile(profile) end)
        {v, _} = :timer.tc(fn -> DfCM.verify_projection_identity(envelope) end)
        {c, v}
      end
      |> Enum.unzip()

    {median(compile), median(verify)}
  end

  defp median(samples), do: samples |> Enum.sort() |> Enum.at(div(length(samples), 2))

  defp within?({compile_us, verify_us}, ceiling_us),
    do: verify_us <= ceiling_us and verify_us <= compile_us * @max_ratio

  for {tier, ceiling_us} <- @tiers do
    test "verify_projection_identity stays within its regression bound at #{tier} resources" do
      tier = unquote(tier)
      ceiling_us = unquote(ceiling_us)
      profile = ConnectedProfile.profile(tier)
      {:ok, envelope} = DfCM.compile(profile)
      assert {:ok, _} = DfCM.verify_projection_identity(envelope)

      observed =
        Enum.reduce_while(1..@attempts, [], fn _, acc ->
          m = medians(profile, envelope)
          if within?(m, ceiling_us), do: {:halt, [m | acc]}, else: {:cont, [m | acc]}
        end)

      {compile_us, verify_us} = Enum.min_by(observed, fn {_c, v} -> v end)

      assert verify_us <= ceiling_us,
             "verify median #{verify_us}us exceeds absolute ceiling #{ceiling_us}us at tier #{tier} " <>
               "(attempts: #{inspect(observed)})"

      assert verify_us <= compile_us * @max_ratio,
             "verify median #{verify_us}us exceeds #{@max_ratio} x compile median #{compile_us}us " <>
               "(attempts: #{inspect(observed)})"
    end
  end
end
