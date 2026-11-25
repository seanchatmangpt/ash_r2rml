# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.MutationCourtScriptTest do
  @moduledoc """
  Structural checks on `bin/mutation-court`: it exists, is executable, parses under `bash -n`,
  and every mutation names a target test file (and mutation target source) that exists on disk.
  The court itself is run by the coordinator, not by this test.
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @script Path.join(@root, "bin/mutation-court")

  test "script exists and is executable" do
    assert File.regular?(@script)
    {:ok, %File.Stat{mode: mode}} = File.stat(@script)
    assert Bitwise.band(mode, 0o111) != 0
  end

  test "script passes bash -n" do
    {out, status} = System.cmd("bash", ["-n", @script], stderr_to_stdout: true)
    assert status == 0, out
  end

  test "every mutation names an existing target test file" do
    body = File.read!(@script)

    mutate_blocks =
      Regex.scan(~r/^mutate\s+(M\w+)\s.*?(test\/[\w\/]+\.exs)/ms, body)

    ids = Enum.map(mutate_blocks, fn [_, id, _] -> id end)

    for id <- ~w(M1a M1b M1c M2a M2b M3a M3b M4a M4b M5 M6 M7 M8) do
      assert id in ids, "mutation #{id} missing from bin/mutation-court"
    end

    for [_, id, test_file] <- mutate_blocks do
      assert File.regular?(Path.join(@root, test_file)),
             "#{id} targets missing test file #{test_file}"
    end
  end

  test "every mutated source file variable resolves to an existing file" do
    body = File.read!(@script)

    for [_, var, path] <- Regex.scan(~r/^([A-Z_]+)="((?:lib|mix)[\w\/\.]*)"$/m, body),
        var != "OFFENDER" do
      assert File.regular?(Path.join(@root, path)), "#{var} points at missing #{path}"
    end
  end
end
