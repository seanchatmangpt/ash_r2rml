# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshR2rml.Gen.SemanticTypes do
    use Igniter.Mix.Task
    @shortdoc "Generates admitted semantic types and manifest through Igniter"

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      source = AshR2RML.Mix.SemanticTypes.load_source(igniter.args.argv)
      plan = case AshR2RML.SemanticTypes.plan(source) do
        {:ok, plan} -> plan
        {:error, refusals} -> Mix.raise(AshR2RML.Mix.SemanticTypes.format_refusals(refusals))
      end

      app_name = Igniter.Project.Application.app_name(igniter)
      files = case AshR2RML.SemanticTypes.Generator.igniter_files(plan, app_name) do
        {:ok, files} -> files
        {:error, reason} -> Mix.raise("semantic type generation failed: #{inspect(reason)}")
      end

      igniter = Enum.reduce(files, igniter, fn {path, content}, acc ->
        Igniter.create_new_file(acc, path, content, on_exists: :overwrite)
      end)

      Igniter.add_notice(igniter, "Semantic type plan #{plan.id} admitted; generated projections remain CONSTRUCT-only.")
    end
  end
else
  defmodule Mix.Tasks.AshR2rml.Gen.SemanticTypes do
    use Mix.Task
    @shortdoc "Explains how to enable the Igniter semantic type generator"
    @impl Mix.Task
    def run(_args) do
      Mix.raise("ash_r2rml.gen.semantic_types requires Igniter; add {:igniter, \"~> 0.6\", only: [:dev, :test]} or run through mix igniter.install")
    end
  end
end
