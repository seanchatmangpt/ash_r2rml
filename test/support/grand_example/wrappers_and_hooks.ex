# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExample.Wrappers do
  @moduledoc """
  Execution wrapper functions for `around` steps in Reactor.
  """
  require Logger

  def with_audit_span(arguments, context, _options, callback) do
    Logger.debug("[ZachPostAGI] Entering around span with args: #{inspect(Map.keys(arguments))}")
    start_time = System.monotonic_time()

    case callback.(arguments, context) do
      {:ok, result} ->
        duration = System.monotonic_time() - start_time
        Logger.debug("[ZachPostAGI] Exiting around span in #{duration}ns")
        {:ok, result}

      {:error, reason} ->
        Logger.warning("[ZachPostAGI] Around span failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

defmodule AshR2RML.GrandExample.Hooks do
  @moduledoc """
  Lifecycle hooks for `group` steps in Reactor.
  """
  require Logger

  @doc "Before hook for group: returns {:ok, arguments, context, steps}"
  def setup_preflight(arguments, context, steps) do
    Logger.debug("[ZachPostAGI] Group before_all setup executing for #{length(steps)} steps")
    new_context = Map.put(context, :preflight_initialized_at, System.system_time(:millisecond))
    {:ok, arguments, new_context, steps}
  end

  @doc "After hook for group: returns {:ok, result}"
  def cleanup_preflight(results) do
    Logger.debug("[ZachPostAGI] Group after_all cleanup executing for results: #{inspect(Map.keys(results))}")
    {:ok, results}
  end
end
