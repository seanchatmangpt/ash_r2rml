# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# RFC-closure (v26.9.16, A2A-2608/A2A-2612) projection-identity benchmark.
#
# Measures the fail-closed drift check `AshR2RML.DfCM.Compiler.verify_projection_identity/1`
# against the DfCM compile it guards, plus the exact-stage manufacturing verification.
# Correctness is verified per tier before timing (untouched envelope admitted, one-byte
# R2RML drift refused). No external engine is exercised.
#
#   MIX_ENV=test mix run bench/projection_identity.exs
#   BENCH_TIERS=10,100 BENCH_TIME=2 MIX_ENV=test mix run bench/projection_identity.exs

alias AshR2RML.DfCM.Compiler, as: DfCM
alias AshR2RML.Test.RFCClosure.ConnectedProfile

tiers =
  case System.get_env("BENCH_TIERS") do
    nil -> [10, 100, 1000]
    csv -> csv |> String.split(",") |> Enum.map(&String.to_integer/1)
  end

time = System.get_env("BENCH_TIME", "3") |> String.to_integer()

envelopes =
  Map.new(tiers, fn n ->
    {:ok, envelope} = DfCM.compile(ConnectedProfile.profile(n))
    {:ok, _} = DfCM.verify_projection_identity(envelope)

    drifted = %{envelope | compilation: %{envelope.compilation | r2rml: envelope.compilation.r2rml <> " "}}
    {:error, %{code: :REFUSED_PROJECTION_DRIFT}} = DfCM.verify_projection_identity(drifted)
    {n, envelope}
  end)

IO.puts("== Correctness verified for tiers #{inspect(tiers)} (admit untouched, refuse 1-byte drift) ==")
IO.puts("elixir=#{System.version()} otp=#{System.otp_release()}")

jobs =
  Enum.flat_map(tiers, fn n ->
    envelope = Map.fetch!(envelopes, n)
    profile = ConnectedProfile.profile(n)
    c = envelope.compilation

    files = %{
      "ash.ex" => c.ash_source,
      "migration.exs" => c.ecto_migration,
      "schema.sql" => c.postgres_ddl,
      "mapping.r2rml.ttl" => c.r2rml,
      "shapes.shacl.ttl" => c.shacl
    }

    plan = AshR2RML.Manufacturing.plan(files, envelope.session_identity)

    [
      {"#{String.pad_leading(to_string(n), 4)} dfcm_compile", fn -> DfCM.compile(profile) end},
      {"#{String.pad_leading(to_string(n), 4)} verify_projection_identity",
       fn -> DfCM.verify_projection_identity(envelope) end},
      {"#{String.pad_leading(to_string(n), 4)} manufacturing verify_staged",
       fn -> AshR2RML.Manufacturing.verify_staged(plan, plan.file_hashes) end}
    ]
  end)
  |> Map.new()

Benchee.run(jobs, time: time, warmup: 1, memory_time: 1, print: [configuration: false])
