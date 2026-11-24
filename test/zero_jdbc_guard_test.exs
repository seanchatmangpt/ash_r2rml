# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ZeroJdbcGuardTest do
  @moduledoc """
  The shipped package contains zero Java and zero JDBC: no Ontop/JDBC module, source text,
  dependency, or packaged file. `AshR2RML.OBDA.InMemory` is the sole runtime OBDA backend.
  """
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @pattern ~r/jdbc|ontop/i
  @doc_pattern ~r/jdbc:|\.jar\b|ontop\/ontop|docker compose/i

  defp files(globs) do
    globs
    |> Enum.flat_map(&Path.wildcard(Path.join(@root, &1)))
    |> Enum.filter(&File.regular?/1)
  end

  defp offenders(paths, pattern), do: Enum.filter(paths, &(File.read!(&1) =~ pattern))

  test "no lib source mentions jdbc or ontop" do
    paths = files(["lib/**/*.ex"])
    assert paths != []
    assert offenders(paths, @pattern) == []
  end

  test "mix.exs and mix.lock mention neither jdbc nor ontop" do
    paths = files(["mix.exs", "mix.lock"])
    assert length(paths) == 2
    assert offenders(paths, @pattern) == []
  end

  test "mix.exs declares no postgrex, jdbc, or java dependency" do
    deps = Mix.Project.config()[:deps] |> Enum.map(&(&1 |> elem(0) |> Atom.to_string()))
    assert deps != []
    assert Enum.filter(deps, &(&1 =~ ~r/postgrex|jdbc|java/i)) == []
    assert Enum.filter(files(["mix.exs"]), &(File.read!(&1) =~ ~r/postgrex|jdbc|java/i)) == []
  end

  test "config and CI files mention neither jdbc nor ontop" do
    paths = files(["config/**/*", ".github/**/*"])
    assert paths != []
    assert offenders(paths, @pattern) == []
  end

  test "shipped docs carry no jdbc url, jar, ontop image, or docker compose" do
    paths = files(["README.md", "AGENTS.md", "usage-rules.md", "usage-rules/**/*"])
    assert paths != []
    assert offenders(paths, @doc_pattern) == []
  end

  test "no Ontop/JDBC module is loadable" do
    for mod <- [AshR2RML.OBDA.Ontop, AshR2RML.OBDA.Adapter.OntopConfig, AshR2RML.OntopCompliance] do
      refute Code.ensure_loaded?(mod), "#{inspect(mod)} must not exist"
    end

    {:ok, mods} = :application.get_key(:ash_r2rml, :modules)
    assert mods != []
    assert Enum.filter(mods, &(Atom.to_string(&1) =~ @pattern)) == []
  end

  test "package files list contains no jdbc/ontop path" do
    package_files = Mix.Project.config()[:package][:files]

    files =
      package_files
      |> Enum.flat_map(&Path.wildcard(Path.join(@root, &1 <> "/**/*")))
      |> Enum.concat(package_files)

    assert files != []
    assert Enum.filter(files, &(&1 =~ ~r/jdbc|ontop|\.jar$/i)) == []
  end
end
