# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshR2rml.Install do
    use Igniter.Mix.Task

    @shortdoc "Installs AshR2RML into an Ash project using Igniter"
    @moduledoc """
    Automated Igniter installer task for AshR2RML.

    Adds `AshR2RML.Resource` extensions, configures `.formatter.exs`, and sets up
    `r2rml` Spark DSL formatting.

    ## Usage

        mix igniter.install ash_r2rml
        mix ash_r2rml.install
    """

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.Project.Formatter.import_dep(:ash_r2rml)
      |> Igniter.Project.Formatter.add_formatter_plugin(AshR2RML.Formatter)
      |> Igniter.add_notice("""
      AshR2RML installed successfully!

      Add `extensions: [AshR2RML.Resource]` to your Ash.Resource modules:

          use Ash.Resource,
            domain: MyApp.Domain,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshR2RML.Resource]

          r2rml do
            class "https://schema.org/Person"
            subject do
              template "https://example.org/people/{id}"
            end
          end
      """)
    end
  end
else
  defmodule Mix.Tasks.AshR2rml.Install do
    use Mix.Task

    @shortdoc "Installs AshR2RML (manual instructions)"

    @impl Mix.Task
    def run(_args) do
      Mix.shell().info("""
      AshR2RML manual installation steps:

      1. Add `:ash_r2rml` to your `mix.exs` dependencies:
         {:ash_r2rml, "~> 0.1.0"}

      2. Add `import_deps: [:ash_r2rml]` and `plugins: [AshR2RML.Formatter]` to your `.formatter.exs`.

      3. Add `extensions: [AshR2RML.Resource]` to your `Ash.Resource` modules.
      """)
    end
  end
end
