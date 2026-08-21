# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Middleware.TelemetryLogger do
  @moduledoc """
  Reactor middleware: structured lifecycle and step telemetry logging for the
  AshR2RML pipeline. Emits real `:telemetry` events for OCEL v2 event capture.
  """

  require Logger

  use Reactor.Middleware

  @impl Reactor.Middleware
  def init(context) do
    start_time = System.monotonic_time()
    Logger.debug("[AshR2RML.Reactor] pipeline starting")
    {:ok, Map.put(context, :_ash_r2rml_reactor_start_time, start_time)}
  end

  @impl Reactor.Middleware
  def complete(result, context) do
    duration =
      case Map.get(context, :_ash_r2rml_reactor_start_time) do
        nil -> 0
        start -> System.monotonic_time() - start
      end

    :telemetry.execute(
      [:ash_r2rml, :reactor, :pipeline, :stop],
      %{duration: duration},
      %{result: result, context: context}
    )

    Logger.debug("[AshR2RML.Reactor] pipeline completed")
    {:ok, result}
  end

  @impl Reactor.Middleware
  def error(errors, context) do
    Logger.warning("[AshR2RML.Reactor] pipeline failed: #{inspect(errors)}")

    :telemetry.execute(
      [:ash_r2rml, :reactor, :pipeline, :exception],
      %{duration: 0},
      %{errors: errors, context: context}
    )

    :ok
  end

  @impl Reactor.Middleware
  def event({:run_start, arguments}, step, context) do
    Logger.debug("[AshR2RML.Reactor] step #{inspect(step.name)} starting — args: #{inspect(Map.keys(arguments))}")
    {:ok, Map.put(context, {step.name, :start_time}, System.monotonic_time())}
  end

  @impl Reactor.Middleware
  def event({:run_complete, result}, step, context) do
    duration =
      case Map.get(context, {step.name, :start_time}) do
        nil -> 0
        start -> System.monotonic_time() - start
      end

    :telemetry.execute(
      [:ash_r2rml, :reactor, :step, :stop],
      %{duration: duration},
      %{step: step.name, result: result, context: context}
    )

    :ok
  end

  def event(_event, _step, _context), do: :ok
end
