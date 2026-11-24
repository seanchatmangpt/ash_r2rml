# SPDX-FileCopyrightText: 2026 ash_r2rml contributors
# SPDX-License-Identifier: MIT

# Umbrella OBDA bench: runs B1..B6 (bench/b<N>*.exs, case-insensitive) in sequence via
# Code.require_file, aggregates outcomes (any failure => exit 1) and writes
# bench/results/obda_bench.json + obda_bench.md.
#
# Run: MIX_ENV=test mix run bench/obda_bench.exs
#
# A sub-bench fails when it raises/throws/exits, or when it sets the process-dictionary-free
# convention of calling System.halt/1 itself (halting aborts the umbrella, which is the loud
# outcome). Sub-benches signal a soft failure by raising.

defmodule ObdaBench.Umbrella do
  @bench_dir __DIR__
  @results_dir Path.join(__DIR__, "results")

  def run do
    File.mkdir_p!(@results_dir)
    started = System.monotonic_time(:millisecond)

    rows = Enum.map(1..6, &run_one/1)

    total_ms = System.monotonic_time(:millisecond) - started
    code = if Enum.any?(rows, &(&1.status != "pass")), do: 1, else: 0

    summary = %{
      suite: "obda_bench",
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      total_ms: total_ms,
      exit_code: code,
      benches: rows
    }

    File.write!(Path.join(@results_dir, "obda_bench.json"), Jason.encode!(summary, pretty: true))
    File.write!(Path.join(@results_dir, "obda_bench.md"), markdown(summary))

    IO.puts(markdown(summary))
    if code != 0, do: System.halt(code)
  end

  defp find_script(n) do
    @bench_dir
    |> File.ls!()
    |> Enum.filter(fn f ->
      f != "obda_bench.exs" and String.match?(f, ~r/^b#{n}(?!\d).*\.exs$/i)
    end)
    |> Enum.sort()
    |> List.first()
  end

  defp run_one(n) do
    id = "B#{n}"

    case find_script(n) do
      nil ->
        %{id: id, script: nil, status: "missing", ms: 0, detail: "no bench/b#{n}*.exs found"}

      file ->
        t0 = System.monotonic_time(:millisecond)
        {status, detail} = execute(Path.join(@bench_dir, file))
        ms = System.monotonic_time(:millisecond) - t0
        %{id: id, script: file, status: status, ms: ms, detail: detail}
    end
  end

  defp execute(path) do
    Code.require_file(path)
    {"pass", ""}
  rescue
    e -> {"fail", Exception.format(:error, e, __STACKTRACE__) |> String.slice(0, 2000)}
  catch
    kind, reason -> {"fail", Exception.format(kind, reason, __STACKTRACE__) |> String.slice(0, 2000)}
  end

  defp markdown(%{benches: rows} = s) do
    head = """
    # OBDA bench scorecard

    Generated: #{s.generated_at} | total: #{s.total_ms} ms | exit: #{s.exit_code}

    | Bench | Script | Status | ms |
    |---|---|---|---|
    """

    body =
      Enum.map_join(rows, "\n", fn r ->
        "| #{r.id} | #{r.script || "-"} | #{String.upcase(r.status)} | #{r.ms} |"
      end)

    fails =
      rows
      |> Enum.filter(&(&1.detail != ""))
      |> Enum.map_join("\n", fn r -> "\n## #{r.id} detail\n\n```\n#{r.detail}\n```" end)

    head <> body <> "\n" <> fails <> "\n"
  end
end

ObdaBench.Umbrella.run()
