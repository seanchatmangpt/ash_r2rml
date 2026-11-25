# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshR2rml.Render do
  @shortdoc "Renders R2RML Turtle for Ash resources or domains"
  @moduledoc """
  Renders W3C R2RML Turtle to stdout for one or more Ash resources or domains.

      mix ash_r2rml.render MyApp.Person MyApp.Domain

  Raises with the refusal detail when compilation or rendering is refused.
  """
  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {_opts, args, invalid} = OptionParser.parse(argv, strict: [])

    if invalid != [] or args == [] do
      Mix.raise("usage: mix ash_r2rml.render <Module> [<Module>...]")
    end

    Mix.Task.run("compile")

    modules = Enum.map(args, &resolve_module!/1)

    with {:ok, bundle} <- AshR2RML.Compiler.compile(modules),
         {:ok, turtle} <- AshR2RML.R2RML.render(bundle) do
      Mix.shell().info(String.trim_trailing(turtle))
    else
      {:error, %AshR2RML.Refusal{code: code, detail: detail}} ->
        Mix.raise("#{code}: #{detail}")

      {:error, other} ->
        Mix.raise("render refused: #{inspect(other)}")
    end
  end

  # Resolves only modules whose atoms already exist and that are loadable;
  # never mints atoms from CLI input.
  @spec resolve_module!(String.t()) :: module()
  defp resolve_module!(name) do
    module =
      try do
        Module.safe_concat([name])
      rescue
        ArgumentError -> Mix.raise("unknown module: #{name}")
      end

    if Code.ensure_loaded?(module) do
      module
    else
      Mix.raise("module not loadable: #{name}")
    end
  end
end
