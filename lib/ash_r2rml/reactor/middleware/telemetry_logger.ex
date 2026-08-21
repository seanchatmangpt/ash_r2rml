# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Reactor.Middleware.TelemetryLogger do
  @moduledoc """
  Reactor middleware for structured lifecycle telemetry and OCEL v2 capture.

  Every Reactor invocation receives one execution identifier in middleware
  context. Step and pipeline telemetry carries that identifier plus a stable
  content identity for the produced result, allowing the existing OCEL stream
  to correlate concurrent steps without turning scheduler order or wall-clock
  time into semantic identity.
  """

  require Logger

  use Reactor.Middleware

  alias AshR2RML.Evidence

  @impl Reactor.Middleware
  def init(context) do
    start_time = System.monotonic_time()
    execution_id = Evidence.execution_id(context) || Ash.UUIDv7.generate()

    Logger.debug("[AshR2RML.Reactor] pipeline starting execution=#{execution_id}")

    {:ok,
     context
     |> Map.put(:_ash_r2rml_reactor_start_time, start_time)
     |> Map.put(:ash_r2rml_execution_id, execution_id)}
  end

  @impl Reactor.Middleware
  def complete(result, context) do
    duration = elapsed(context, :_ash_r2rml_reactor_start_time)
    execution_id = Evidence.execution_id(context)

    :telemetry.execute(
      [:ash_r2rml, :reactor, :pipeline, :stop],
      %{duration: duration},
      %{
        result: result,
        context: context,
        execution_id: execution_id,
        result_evidence_id: Evidence.id(result)
      }
    )

    Logger.debug("[AshR2RML.Reactor] pipeline completed execution=#{execution_id}")
    {:ok, result}
  end

  @impl Reactor.Middleware
  def error(errors, context) do
    execution_id = Evidence.execution_id(context)
    Logger.warning("[AshR2RML.Reactor] pipeline failed execution=#{execution_id}: #{inspect(errors)}")

    :telemetry.execute(
      [:ash_r2rml, :reactor, :pipeline, :exception],
      %{duration: elapsed(context, :_ash_r2rml_reactor_start_time)},
      %{
        errors: errors,
        context: context,
        execution_id: execution_id,
        error_evidence_id: Evidence.id(errors)
      }
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
    duration = elapsed(context, {step.name, :start_time})

    :telemetry.execute(
      [:ash_r2rml, :reactor, :step, :stop],
      %{duration: duration},
      %{
        step: step.name,
        result: result,
        context: context,
        execution_id: Evidence.execution_id(context),
        result_evidence_id: Evidence.id(result)
      }
    )

    :ok
  end

  def event(_event, _step, _context), do: :ok

  defp elapsed(context, key) do
    case Map.get(context, key) do
      nil -> 0
      start -> System.monotonic_time() - start
    end
  end
end
