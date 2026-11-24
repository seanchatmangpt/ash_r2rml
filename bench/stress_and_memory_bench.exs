# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT
#
# Umbrella for the stress suite. Usage:
#   mix run bench/stress_and_memory_bench.exs [--seconds N]
#
# Runs bench/stress/{s1_s2,s3_s4,s5_storm,s6_soak}.exs in sequence, each in its own
# `mix run` OS process (so a script's System.halt/1 cannot kill the umbrella and its
# exit code is captured), passing --seconds through. Writes bench/results/stress.json
# and bench/results/stress.md. Exit: 0 PASS, 1 FAIL, 2 SUBJECT MISSING, 3 LOUD SKIP.
# Aggregate precedence: 1 > 2 > 3 > 0.

defmodule AshR2RML.Bench.StressUmbrella do
  @moduledoc false

  @scripts ["s1_s2", "s3_s4", "s5_storm", "s6_soak"]

  def main(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [seconds: :integer])
    seconds = Keyword.get(opts, :seconds)
    root = File.cwd!()

    results = Enum.map(@scripts, &run_one(&1, root, seconds))

    aggregate = aggregate(Enum.map(results, & &1.exit))
    File.mkdir_p!(Path.join(root, "bench/results"))
    File.write!(Path.join(root, "bench/results/stress.json"), json(results, aggregate, seconds))
    File.write!(Path.join(root, "bench/results/stress.md"), scorecard(results, aggregate))

    IO.puts(scorecard(results, aggregate))
    System.halt(aggregate)
  end

  defp run_one(name, root, seconds) do
    rel = "bench/stress/#{name}.exs"
    started = System.monotonic_time(:millisecond)

    code =
      if File.regular?(Path.join(root, rel)) do
        args = ["run", rel] ++ if(seconds, do: ["--seconds", Integer.to_string(seconds)], else: [])
        {_, status} = System.cmd("mix", args, into: IO.stream(:stdio, :line), stderr_to_stdout: true)
        status
      else
        IO.puts("SUBJECT MISSING: #{rel}")
        2
      end

    %{name: name, script: rel, exit: code, ms: System.monotonic_time(:millisecond) - started}
  end

  defp aggregate(codes) do
    cond do
      Enum.any?(codes, &(&1 not in [0, 2, 3])) -> 1
      1 in codes -> 1
      2 in codes -> 2
      3 in codes -> 3
      true -> 0
    end
  end

  defp label(0), do: "PASS"
  defp label(2), do: "SUBJECT MISSING"
  defp label(3), do: "LOUD SKIP"
  defp label(_), do: "FAIL"

  defp scorecard(results, agg) do
    rows =
      Enum.map_join(results, "\n", fn r ->
        "| #{r.name} | #{r.exit} | #{label(r.exit)} | #{r.ms} |"
      end)

    """
    # Stress scorecard

    | script | exit | verdict | ms |
    |---|---|---|---|
    #{rows}

    Aggregate: exit #{agg} (#{label(agg)})
    """
  end

  defp json(results, agg, seconds) do
    items =
      Enum.map_join(results, ",", fn r ->
        ~s({"name":"#{r.name}","script":"#{r.script}","exit":#{r.exit},"verdict":"#{label(r.exit)}","ms":#{r.ms}})
      end)

    ~s({"seconds":#{seconds || "null"},"aggregate_exit":#{agg},"aggregate_verdict":"#{label(agg)}","results":[#{items}]}\n)
  end
end

AshR2RML.Bench.StressUmbrella.main(System.argv())
