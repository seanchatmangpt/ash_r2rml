# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.NoRetiredWordGateTest do
  @moduledoc """
  Source-scan gate: the retired-surface word must not occur (case-insensitive) in any `lib/`
  or `test/` Elixir file. The pattern is assembled from parts so this file never contains the
  word itself and therefore never trips its own gate.
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)

  defp pattern, do: Regex.compile!(Enum.join(["leg", "acy"]), "i")

  defp scanned_files do
    Path.wildcard(Path.join(@root, "{lib,test}/**/*.{ex,exs}"))
  end

  test "the gate sees the real source tree (non-vacuity)" do
    files = scanned_files()
    assert Enum.any?(files, &String.ends_with?(&1, "lib/ash_r2rml/obda.ex"))
    own_name = "test/no_" <> Enum.join(["leg", "acy"]) <> "_gate_test.exs"
    assert Enum.any?(files, &String.ends_with?(&1, own_name))
  end

  test "the pattern matches in every case variant (non-vacuity)" do
    word = Enum.join(["leg", "acy"])

    for variant <- [word, String.upcase(word), String.capitalize(word)] do
      assert Regex.match?(pattern(), "x #{variant} y")
    end

    refute Regex.match?(pattern(), "a clean line")
  end

  test "no lib/ or test/ file contains the retired word" do
    regex = pattern()

    offenders =
      for file <- scanned_files(),
          {line, number} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          Regex.match?(regex, line) do
        "#{Path.relative_to(file, @root)}:#{number}: #{String.trim(line)}"
      end

    assert offenders == [], "retired word found:\n" <> Enum.join(offenders, "\n")
  end
end
