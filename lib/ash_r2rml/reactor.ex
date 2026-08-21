# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Reactor.Step) do
  defmodule AshR2RML.Reactor.CompileR2RML do
    @moduledoc """
    Reactor Step for compiling Ash resources or semantic profiles into R2RML Turtle.

    ## Arguments

    - `:resources` - A resource module, list of resource modules, or profile map to compile.

    ## Example

        step :compile_r2rml, AshR2RML.Reactor.CompileR2RML do
          argument :resources, [MyApp.User, MyApp.Organization]
        end
    """

    use Reactor.Step

    @impl Reactor.Step
    def run(arguments, _context, _options) do
      case Map.fetch(arguments, :resources) do
        {:ok, resources} ->
          case AshR2RML.Compiler.compile(resources) do
            {:ok, bundle_or_compilation} -> {:ok, bundle_or_compilation}
            {:error, refusal} -> {:error, refusal}
          end

        :error ->
          {:error, "Missing required argument :resources"}
      end
    end
  end
else
  defmodule AshR2RML.Reactor.CompileR2RML do
    @moduledoc "Reactor step helper for AshR2RML compilation."
    def run(_arguments, _context, _options) do
      {:error, "Reactor library is not loaded"}
    end
  end
end
