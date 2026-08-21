# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshR2rml.GenerateDocs do
  use Mix.Task

  @shortdoc "Generates Markdown DSL cheat sheet for AshR2RML"
  @moduledoc """
  Generates `documentation/reference/dsl_cheatsheet.md` using `Spark.CheatSheet`.

  ## Usage

      mix ash_r2rml.generate_docs
  """

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    content = AshR2RML.CheatSheet.generate()
    target_path = "documentation/reference/dsl_cheatsheet.md"

    File.mkdir_p!(Path.dirname(target_path))
    File.write!(target_path, content)

    Mix.shell().info("Successfully generated DSL cheat sheet at #{target_path}")
  end
end
