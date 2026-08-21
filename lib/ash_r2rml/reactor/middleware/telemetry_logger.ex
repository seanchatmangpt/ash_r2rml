# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Middleware.TelemetryLogger do
  @moduledoc """
  Reactor middleware: structured lifecycle and step telemetry logging for the
  AshR2RML pipeline.

  Implements the `Reactor.Middleware` behaviour, emitting `Logger` messages at
  pipeline init, completion, error, and at the start of each individual step.
  All callbacks are optional so non-implemented lifecycle hooks are simply
  omitted.
  """

  require Logger

  use Reactor.Middleware

  @impl Reactor.Middleware
  def init(context) do
    Logger.debug("[AshR2RML.Reactor] pipeline starting")
    {:ok, context}
  end

  @impl Reactor.Middleware
  def complete(result, _context) do
    Logger.debug("[AshR2RML.Reactor] pipeline completed")
    {:ok, result}
  end

  @impl Reactor.Middleware
  def error(errors, _context) do
    Logger.warning("[AshR2RML.Reactor] pipeline failed: #{inspect(errors)}")
    :ok
  end

  @impl Reactor.Middleware
  def event({:run_start, arguments}, step, _context) do
    Logger.debug("[AshR2RML.Reactor] step #{inspect(step.name)} starting — args: #{inspect(Map.keys(arguments))}")
    :ok
  end

  def event(_event, _step, _context), do: :ok
end
