# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ZeroJdbcGuardTest do
  @moduledoc """
  The shipped package contains zero Java and zero JDBC: no Ontop/JDBC module, source text,
  dependency, or packaged file. `AshR2RML.OBDA.InMemory` is the sole runtime OBDA backend.
  """
  use ExUnit.Case, async: true

  @pattern ~r/jdbc|ontop/i

  test "no lib source mentions jdbc or ontop" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(&(File.read!(&1) =~ @pattern))

    assert offenders == []
  end

  test "mix.exs mentions neither jdbc nor ontop" do
    refute File.read!("mix.exs") =~ @pattern
  end

  test "no Ontop/JDBC module is loadable" do
    for mod <- [AshR2RML.OBDA.Ontop, AshR2RML.OBDA.Adapter.OntopConfig, AshR2RML.OntopCompliance] do
      refute Code.ensure_loaded?(mod), "#{inspect(mod)} must not exist"
    end

    {:ok, mods} = :application.get_key(:ash_r2rml, :modules)
    assert Enum.filter(mods, &(Atom.to_string(&1) =~ @pattern)) == []
  end

  test "package files list contains no jdbc/ontop path" do
    files =
      Mix.Project.config()[:package][:files]
      |> Enum.flat_map(&Path.wildcard(&1 <> "/**/*"))
      |> Enum.concat(Mix.Project.config()[:package][:files])

    assert Enum.filter(files, &(&1 =~ ~r/jdbc|ontop|\.jar$/i)) == []
  end
end
