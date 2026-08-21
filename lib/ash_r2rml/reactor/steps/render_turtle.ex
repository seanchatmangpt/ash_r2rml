# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Steps.RenderTurtle do
  @moduledoc """
  Reactor step: render the normalized mapping bundle into W3C R2RML Turtle.

  Calls `AshR2RML.R2RML.render/1` and returns `{:ok, turtle_string}` on
  success.  Render failures are non-retryable; the compensate callback logs
  the error and returns `:ok` to allow the reactor to continue rolling back.

  ## Arguments

  - `:bundle` — `%AshR2RML.Mapping.Bundle{}` ready for serialization.
  """

  require Logger

  use Reactor.Step

  @impl Reactor.Step
  def run(%{bundle: bundle}, _context, _options) do
    AshR2RML.R2RML.render(bundle)
  end

  @impl Reactor.Step
  def compensate(reason, _arguments, _context, _options) do
    Logger.warning("[AshR2RML.Reactor.Steps.RenderTurtle] render failed: #{inspect(reason)}")
    :ok
  end
end
