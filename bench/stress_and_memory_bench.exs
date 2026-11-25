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

  @default_layers ~w(ets simple mnesia embedded sqlite csv custom)
  @all_layers @default_layers ++ ~w(postgres mysql)

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          seconds: :integer,
          layers: :string,
          digest_check: :boolean,
          legacy: :boolean,
          rows: :integer
        ]
      )

    if Keyword.has_key?(opts, :layers) or Keyword.get(opts, :digest_check, false) do
      layers_main(opts)
    else
      legacy_main(opts)
    end
  end

  # ---- layered mode ----

  defp layers_main(opts) do
    root = File.cwd!()
    seconds = Keyword.get(opts, :seconds)

    layers =
      case Keyword.get(opts, :layers, Enum.join(@default_layers, ",")) do
        "all" -> @all_layers
        csv -> csv |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.uniq()
      end

    unknown = Enum.reject(layers, &(&1 in @all_layers))

    if unknown != [] do
      IO.puts(:stderr, "unknown layer(s): #{Enum.join(unknown, ", ")}; known: #{Enum.join(@all_layers, ",")}")
      System.halt(2)
    end

    Code.require_file(Path.join(root, "bench/support/layer_common.exs"))

    results = Enum.map(layers, &run_layer(&1, root, opts))

    digests =
      for %{status: :ran, digest: d} = r <- results, is_binary(d), do: {r.layer, d}

    digest_ok = digests |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() <= 1

    IO.puts("\nCanonical digests:")
    Enum.each(digests, fn {l, d} -> IO.puts("  #{String.pad_trailing(l, 10)} #{Base.encode16(d, case: :lower)}") end)
    IO.puts("  equal across layers: #{digest_ok}")

    code = layers_exit(results, digest_ok)
    File.mkdir_p!(Path.join(root, "bench/results"))
    File.write!(Path.join(root, "bench/results/stress_layers.json"), layers_json(results, digests, digest_ok, code, seconds))
    md = layers_md(results, digests, digest_ok, code)
    File.write!(Path.join(root, "bench/results/stress_layers.md"), md)
    IO.puts(md)
    System.halt(code)
  end

  defp run_layer("ets", root, opts) do
    if Keyword.get(opts, :legacy, false) do
      started = System.monotonic_time(:millisecond)

      codes =
        for s <- @scripts, do: run_one(s, root, Keyword.get(opts, :seconds)).exit

      agg = aggregate(codes)
      ms = System.monotonic_time(:millisecond) - started

      case agg do
        3 ->
          IO.puts("[SKIP] ets: legacy scripts skipped")
          %{layer: "ets", status: :skipped, reason: "legacy scripts skipped", scenarios: [], digest: nil, ms: ms}

        0 ->
          %{layer: "ets", status: :ran, scenarios: [%{id: :legacy, desc: "legacy per-script path", ok: true, why: nil, ms: ms}], digest: nil, ms: ms}

        c ->
          %{layer: "ets", status: :ran, scenarios: [%{id: :legacy, desc: "legacy per-script path", ok: false, why: "exit #{c}", ms: ms}], digest: nil, ms: ms}
      end
    else
      run_layer_module("ets", root, opts)
    end
  end

  defp run_layer(layer, root, opts), do: run_layer_module(layer, root, opts)

  defp run_layer_module(layer, root, opts) do
    started = System.monotonic_time(:millisecond)
    file = Path.join(root, "bench/stress/layers/#{layer}.exs")

    cond do
      not File.regular?(file) ->
        skip(layer, "layer file missing: bench/stress/layers/#{layer}.exs", started)

      true ->
        try do
          Code.require_file(file)
          mod = Module.concat([Bench.Layer, Macro.camelize(layer)])

          with {:module, ^mod} <- Code.ensure_loaded(mod),
               :ok <- mod.available?(),
               {:ok, ctx} <-
                 mod.setup(
                   [rows: Keyword.get(opts, :rows, 10_000), digest_rows: 500] ++
                     if(opts[:seconds], do: [seconds: opts[:seconds]], else: [])
                 ) do
            try do
              scenarios = Enum.map(mod.scenarios(), &run_scenario(&1, ctx))
              digest = safe_digest(mod, ctx)

              %{
                layer: layer,
                status: :ran,
                scenarios: scenarios,
                digest: digest,
                ms: System.monotonic_time(:millisecond) - started
              }
            after
              safe_teardown(ctx)
            end
          else
            {:skip, reason} -> skip(layer, reason, started)
            {:module, other} -> skip(layer, "module mismatch #{inspect(other)}", started)
            {:error, why} -> skip(layer, "module not loadable: #{inspect(why)}", started)
            other -> skip(layer, "unexpected: #{inspect(other)}", started)
          end
        rescue
          e -> skip(layer, "layer crashed: " <> Exception.message(e), started)
        end
    end
  end

  defp skip(layer, reason, started) do
    IO.puts("[SKIP] #{layer}: #{reason}")

    %{
      layer: layer,
      status: :skipped,
      reason: reason,
      scenarios: [],
      digest: nil,
      ms: System.monotonic_time(:millisecond) - started
    }
  end

  defp run_scenario({id, desc, fun}, ctx) do
    t0 = System.monotonic_time(:millisecond)

    {ok, why} =
      try do
        case fun.(ctx) do
          :ok -> {true, nil}
          {:fail, w} -> {false, inspect(w)}
          other -> {false, "bad return " <> inspect(other)}
        end
      rescue
        e -> {false, "raised: " <> Exception.message(e)}
      catch
        kind, v -> {false, "#{kind}: #{inspect(v)}"}
      end

    ms = System.monotonic_time(:millisecond) - t0
    IO.puts("  #{if ok, do: "PASS", else: "FAIL"} #{id} (#{ms}ms)#{if why, do: " - " <> why, else: ""}")
    %{id: id, desc: desc, ok: ok, why: why, ms: ms}
  end

  defp safe_digest(mod, ctx) do
    mod.canonical_digest(ctx)
  rescue
    e ->
      IO.puts("  FAIL canonical_digest raised: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp safe_teardown(%{teardown: f}) when is_function(f, 0) do
    f.()
  rescue
    e -> IO.puts("  teardown raised: #{Exception.message(e)}")
  end

  defp safe_teardown(_), do: :ok

  defp layers_exit(results, digest_ok) do
    failed? =
      not digest_ok or
        Enum.any?(results, fn r ->
          r.status == :ran and
            (Enum.any?(r.scenarios, &(not &1.ok)) or match?({:error, _}, r.digest))
        end)

    cond do
      failed? -> 1
      Enum.any?(results, &(&1.status == :skipped)) -> 3
      true -> 0
    end
  end

  defp layers_md(results, digests, digest_ok, code) do
    rows =
      Enum.map_join(results, "\n", fn r ->
        case r.status do
          :skipped ->
            "| #{r.layer} | SKIP | - | #{r.reason} | #{r.ms} |"

          :ran ->
            pass = Enum.count(r.scenarios, & &1.ok)
            bad = r.scenarios |> Enum.reject(& &1.ok) |> Enum.map_join("; ", &"#{&1.id}: #{&1.why}")
            verdict = if bad == "" and not match?({:error, _}, r.digest), do: "PASS", else: "FAIL"
            "| #{r.layer} | #{verdict} | #{pass}/#{length(r.scenarios)} | #{bad} | #{r.ms} |"
        end
      end)

    drows =
      Enum.map_join(digests, "\n", fn {l, d} -> "| #{l} | #{Base.encode16(d, case: :lower)} |" end)

    """
    # Stress layers scorecard

    | layer | verdict | scenarios | detail | ms |
    |---|---|---|---|---|
    #{rows}

    ## Canonical digests

    | layer | digest |
    |---|---|
    #{drows}

    Digests equal across executed layers: #{digest_ok}

    Aggregate: exit #{code}
    """
  end

  defp layers_json(results, digests, digest_ok, code, seconds) do
    layer_items =
      Enum.map(results, fn r ->
        scen =
          Enum.map(r.scenarios, fn s ->
            "{" <> kv([id: to_string(s.id), description: s.desc, ok: s.ok, why: s.why, ms: s.ms]) <> "}"
          end)

        digest =
          case r.digest do
            d when is_binary(d) -> Base.encode16(d, case: :lower)
            _ -> nil
          end

        "{" <>
          kv(
            layer: r.layer,
            status: to_string(r.status),
            reason: Map.get(r, :reason),
            digest: digest,
            ms: r.ms
          ) <> ",\"scenarios\":[" <> Enum.join(scen, ",") <> "]}"
      end)

    "{" <>
      kv(seconds: seconds, digests_equal: digest_ok, aggregate_exit: code, digest_count: length(digests)) <>
      ",\"layers\":[" <> Enum.join(layer_items, ",") <> "]}\n"
  end

  defp kv(pairs), do: Enum.map_join(pairs, ",", fn {k, v} -> "\"#{k}\":#{enc(v)}" end)

  defp enc(nil), do: "null"
  defp enc(v) when is_boolean(v), do: to_string(v)
  defp enc(v) when is_integer(v), do: Integer.to_string(v)
  defp enc(v) when is_binary(v), do: inspect(v, binaries: :as_strings) |> esc(v)
  defp enc(v), do: enc(inspect(v))

  defp esc(_, v) do
    body =
      v
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"" <> body <> "\""
  end

  # ---- legacy umbrella (unchanged behavior) ----

  defp legacy_main(opts) do
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
