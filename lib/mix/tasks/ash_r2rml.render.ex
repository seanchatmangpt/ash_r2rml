# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshR2rml.Render do
  @shortdoc "Renders R2RML Turtle for Ash resources or domains"
  @moduledoc """
  Renders W3C R2RML Turtle to stdout for one or more Ash resources or domains.

      mix ash_r2rml.render MyApp.Person MyApp.Domain

  Each argument is the name of an already-compiled resource or domain module. Unknown or
  unloadable names stop the task with the module name; a refusal stops it with the refusal
  code and detail, so fix the named resource and rerun.

  ## Options

    * `-o`, `--output PATH` - write the Turtle to `PATH`; stdout stays empty
    * `--no-compile` - skip compilation and render from the already-built project

  Compiler output is silenced so stdout carries only Turtle.
  """
  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [output: :string, compile: :boolean],
        aliases: [o: :output]
      )

    if invalid != [] or args == [] do
      Mix.raise("usage: mix ash_r2rml.render [-o PATH] [--no-compile] <Module> [<Module>...]")
    end

    build(Keyword.get(opts, :compile, true))

    modules = Enum.map(args, &resolve_module!/1)

    with {:ok, bundle} <- AshR2RML.Compiler.compile(modules),
         {:ok, turtle} <- AshR2RML.R2RML.render(bundle) do
      emit(String.trim_trailing(turtle), opts[:output])
    else
      {:error, %AshR2RML.Refusal{} = refusal} ->
        Mix.raise(refusal_message(refusal))

      {:error, other} ->
        Mix.raise("render refused: #{inspect(other)}")
    end
  end

  defp build(true) do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Quiet)

    try do
      Mix.Task.run("compile")
    after
      Mix.shell(previous)
    end
  end

  defp build(false), do: Mix.Task.run("loadpaths", ["--no-compile"])

  defp emit(turtle, nil), do: IO.puts(turtle)

  defp emit(turtle, path) do
    case File.write(path, turtle <> "\n") do
      :ok -> :ok
      {:error, reason} -> Mix.raise("cannot write #{path}: #{:file.format_error(reason)}")
    end
  end

  defp refusal_message(%AshR2RML.Refusal{code: code, subject: subject} = refusal) do
    "#{code}: #{refusal.detail} (subject: #{inspect(subject)}; " <>
      "evidence: #{inspect(refusal.evidence)})"
  end

  # A compiled-but-unloaded module has no atom in a fresh VM, so `Module.safe_concat/1` would
  # refuse it. This task is a short-lived CLI process, so the name is syntax-checked against an
  # Elixir module-name pattern, concatenated, and then loaded from its `.beam`.
  @module_name ~r/\A(Elixir\.)?[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*\z/

  @spec resolve_module!(String.t()) :: module()
  defp resolve_module!(name) do
    unless Regex.match?(@module_name, name), do: Mix.raise("unknown module: #{name}")

    module = Module.concat([name])

    if Code.ensure_loaded?(module) do
      module
    else
      Mix.raise("module not loadable: #{name}")
    end
  end
end
