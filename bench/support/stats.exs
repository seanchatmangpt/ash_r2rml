# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Bench.Stats do
  @moduledoc """
  Pure statistics and scorecard helpers shared by the bench scripts.

  Samples are microseconds (`time_samples/3`) or any numeric series.

  ## Examples

      iex> AshR2RML.Bench.Stats.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 50)
      5
      iex> AshR2RML.Bench.Stats.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 95)
      10
      iex> AshR2RML.Bench.Stats.mean([2, 4])
      3.0
      iex> AshR2RML.Bench.Stats.exit_code([])
      0
      iex> AshR2RML.Bench.Stats.exit_code([%{metric: "p99"}])
      1
  """

  @min_samples 100
  @default_warmup 10

  @doc "Nearest-rank percentile (`p` in 0..100) of a non-empty numeric list."
  @spec percentile([number()], number()) :: number()
  def percentile([_ | _] = samples, p) when is_number(p) and p >= 0 and p <= 100 do
    sorted = Enum.sort(samples)
    n = length(sorted)
    rank = max(1, ceil(p / 100 * n))
    Enum.at(sorted, rank - 1)
  end

  @doc "Arithmetic mean as a float."
  @spec mean([number()]) :: float()
  def mean([_ | _] = samples), do: Enum.sum(samples) / length(samples)

  @doc "Sample standard deviation (n - 1); 0.0 for a single sample."
  @spec stddev([number()]) :: float()
  def stddev([_]), do: 0.0

  def stddev([_ | _] = samples) do
    m = mean(samples)
    ss = Enum.reduce(samples, 0.0, fn x, acc -> acc + (x - m) * (x - m) end)
    :math.sqrt(ss / (length(samples) - 1))
  end

  @doc """
  Process capability index against an upper spec limit and optional lower limit.

  Returns `:infinity` when the spread is zero and the mean is inside the limits,
  `0.0` when the spread is zero and the mean is outside them.
  """
  @spec cpk([number()], number(), number() | nil) :: float() | :infinity
  def cpk(samples, usl, lsl \\ nil) do
    m = mean(samples)
    s = stddev(samples)

    cond do
      s == 0.0 ->
        if m <= usl and (is_nil(lsl) or m >= lsl), do: :infinity, else: 0.0

      is_nil(lsl) ->
        (usl - m) / (3 * s)

      true ->
        min((usl - m) / (3 * s), (m - lsl) / (3 * s))
    end
  end

  @doc """
  Times `fun` `n` times (floored at #{@min_samples}) after `:warmup` untimed runs
  (default #{@default_warmup}). Returns microseconds per call.
  """
  @spec time_samples((-> any()), pos_integer(), keyword()) :: [non_neg_integer()]
  def time_samples(fun, n, opts \\ []) when is_function(fun, 0) and is_integer(n) do
    warmup = Keyword.get(opts, :warmup, @default_warmup)
    for _ <- 1..warmup//1, do: fun.()

    for _ <- 1..max(n, @min_samples) do
      {us, _} = :timer.tc(fun)
      us
    end
  end

  @doc "Summary map (n, min, mean, stddev, p50, p95, p99, max) of a sample list."
  @spec summarize([number()]) :: map()
  def summarize([_ | _] = samples) do
    %{
      n: length(samples),
      min: Enum.min(samples),
      mean: mean(samples),
      stddev: stddev(samples),
      p50: percentile(samples, 50),
      p95: percentile(samples, 95),
      p99: percentile(samples, 99),
      max: Enum.max(samples)
    }
  end

  @doc """
  Writes `scorecard` as JSON to `bench/results/<name>.json` (relative to the cwd,
  or `:dir`). Returns the written path.
  """
  @spec write_scorecard(String.t(), map(), keyword()) :: Path.t()
  def write_scorecard(name, scorecard, opts \\ []) when is_binary(name) and is_map(scorecard) do
    dir = Keyword.get(opts, :dir, Path.join("bench", "results"))
    File.mkdir_p!(dir)
    path = Path.join(dir, name <> ".json")
    File.write!(path, encode(scorecard) <> "\n")
    path
  end

  @doc "0 when there are no breaches, 1 otherwise."
  @spec exit_code([term()]) :: 0 | 1
  def exit_code([]), do: 0
  def exit_code([_ | _]), do: 1

  @doc "Halts the VM with `exit_code/1`; prints each breach to stderr first."
  @spec exit_with([term()]) :: no_return()
  def exit_with(breaches) do
    Enum.each(breaches, &IO.puts(:stderr, "BREACH: " <> inspect(&1)))
    System.halt(exit_code(breaches))
  end

  # Jason is a runtime dep of the library; the manual encoder is the fallback.
  defp encode(term) do
    if Code.ensure_loaded?(Jason) do
      apply(Jason, :encode!, [normalize(term), [pretty: true]])
    else
      manual(normalize(term))
    end
  end

  defp normalize(:infinity), do: "infinity"
  defp normalize(%{} = m) when not is_struct(m), do: Map.new(m, fn {k, v} -> {to_string(k), normalize(v)} end)
  defp normalize(l) when is_list(l), do: Enum.map(l, &normalize/1)
  defp normalize(a) when is_atom(a) and a not in [nil, true, false], do: Atom.to_string(a)
  defp normalize(t) when is_tuple(t), do: t |> Tuple.to_list() |> normalize()
  defp normalize(other), do: other

  defp manual(m) when is_map(m) do
    "{" <> Enum.map_join(m, ",", fn {k, v} -> manual(to_string(k)) <> ":" <> manual(v) end) <> "}"
  end

  defp manual(l) when is_list(l), do: "[" <> Enum.map_join(l, ",", &manual/1) <> "]"
  defp manual(s) when is_binary(s), do: "\"" <> escape(s) <> "\""
  defp manual(nil), do: "null"
  defp manual(b) when is_boolean(b), do: to_string(b)
  defp manual(n) when is_integer(n), do: Integer.to_string(n)
  defp manual(f) when is_float(f), do: Float.to_string(f)
  defp manual(other), do: manual(inspect(other))

  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end
