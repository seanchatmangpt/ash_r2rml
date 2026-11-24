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

  test "mix.lock carries no jdbc or ontop jar artifact" do
    lock = Path.join(@root, "mix.lock")
    assert File.regular?(lock)
    assert File.read!(lock) =~ ~r/"/
    refute File.read!(lock) =~ ~r/jdbc|ontop|\.jar\b/i
  end

  test "no production dependency on a database driver, jdbc, or java" do
    deps = Mix.Project.config()[:deps]
    assert deps != []

    opts_of = fn
      {_name, opts} when is_list(opts) -> opts
      {_name, _req, opts} when is_list(opts) -> opts
      _ -> []
    end

    prod_names =
      deps
      |> Enum.filter(fn dep ->
        only = opts_of.(dep)[:only]
        is_nil(only) or :prod in List.wrap(only)
      end)
      |> Enum.map(&(&1 |> elem(0) |> Atom.to_string()))

    forbidden = ~w(postgrex ecto_sql exqlite ash_postgres ash_sqlite)

    assert Enum.filter(prod_names, &(&1 in forbidden)) == []
    assert Enum.filter(prod_names, &(&1 =~ ~r/jdbc|java|ontop/i)) == []
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
