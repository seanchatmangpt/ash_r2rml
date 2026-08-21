# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.CompileResources do
  @moduledoc """
  Reactor step: compile a list of Ash resource modules into a normalized
  `AshR2RML.Mapping.Bundle` via `AshR2RML.Compiler.compile_resources/1`.

  ## Arguments

  - `:resources` — a single resource module or list of modules to compile.

  ## Compensate behaviour

  - Typed `%AshR2RML.Refusal{}` errors are non-retryable; compensate returns `:ok`.
  - All other errors trigger a single retry (`max_retries 1` in the pipeline DSL).
  """

  use Reactor.Step

  @impl Reactor.Step
  def run(%{resources: resources}, _context, _options) do
    AshR2RML.Compiler.compile_resources(resources)
  end

  @impl Reactor.Step
  def compensate(%AshR2RML.Refusal{}, _arguments, _context, _options) do
    # Typed semantic refusals are fail-closed; do not retry
    :ok
  end

  def compensate(_reason, _arguments, _context, _options) do
    # Transient / unknown errors: ask the reactor to retry once
    :retry
  end
end
