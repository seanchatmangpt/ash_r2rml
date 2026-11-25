# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ZeroJdbcAndDepsGuardTest do
  use ExUnit.Case, async: true

  @banned_prod [:ash_postgres, :ash_sqlite, :ecto_sql, :postgrex, :exqlite]

  defp dep_envs(opts) when is_list(opts), do: opts |> Keyword.get(:only, :all) |> List.wrap()
  defp dep_envs(_), do: [:all]

  defp dep_name_opts({name, opts}) when is_list(opts), do: {name, opts}
  defp dep_name_opts({name, _req, opts}) when is_list(opts), do: {name, opts}
  defp dep_name_opts({name, _req}), do: {name, []}

  test "banned database deps are never prod/dev dependencies" do
    offenders =
      for dep <- Mix.Project.config()[:deps],
          {name, opts} = dep_name_opts(dep),
          name in @banned_prod,
          envs = dep_envs(opts),
          :all in envs or :prod in envs or :dev in envs,
          do: name

    assert offenders == []
  end

  test "simple_sat and stream_data are test/dev only" do
    for dep <- Mix.Project.config()[:deps],
        {name, opts} = dep_name_opts(dep),
        name in [:simple_sat, :stream_data] do
      assert dep_envs(opts) in [[:test], [:dev, :test]], "#{name} must be test/dev only"
    end
  end

  test "package files are files only, ship install.ex and render.ex, exclude jdbc/ontop/bench/generate_docs" do
    files = Mix.Project.config()[:package][:files]
    assert is_list(files) and files != []
    assert "lib/mix/tasks/ash_r2rml.install.ex" in files
    assert "lib/mix/tasks/ash_r2rml.render.ex" in files
    refute "lib/mix/tasks/ash_r2rml.generate_docs.ex" in files

    for f <- files do
      assert File.regular?(f), "#{f} is not a regular file"
      refute f =~ ~r/jdbc|ontop|docker/i
      refute String.starts_with?(f, "bench/")
    end
  end

  test "compiled application modules contain no Ontop or JDBC modules" do
    {:ok, mods} = :application.get_key(:ash_r2rml, :modules)
    names = Enum.map(mods, &Atom.to_string/1)
    refute Enum.any?(names, &(&1 =~ ~r/ontop|jdbc/i))
  end
end
