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
  def run([]), do: Mix.raise("usage: mix ash_r2rml.render <Module> [<Module>...]")

  def run(args) do
    Mix.Task.run("app.start")

    modules = Enum.map(args, &Module.concat([&1]))

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
end
