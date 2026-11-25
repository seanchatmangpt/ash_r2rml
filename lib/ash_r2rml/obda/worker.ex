# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Worker do
  @moduledoc """
  Bounded, stateless worker isolation for OBDA query evaluation.

  `run/2` executes a zero-arity function in a monitored process capped by
  `max_heap_size` (kill on breach) and a wall-clock timeout. It never raises:
  every failure is returned as `{:error, %AshR2RML.Error{}}` with one of
  `:REFUSED_QUERY_TIMEOUT`, `:REFUSED_MEMORY_LIMIT_EXCEEDED`, `:REFUSED_WORKER_CRASHED`, or
  `:REFUSED_INVALID_OPTION` (a non-positive-integer `:timeout_ms` / `:max_heap_words`).

  A bare `:killed` exit of the worker is attributed to the heap cap: the runtime reports a
  `max_heap_size` kill and an untrappable `:kill` signal identically. Any other exit reason
  is a `:REFUSED_WORKER_CRASHED` with `details.kind == :exit`.

  The worker inherits the caller's `:"$callers"` chain (caller prepended), so ownership-based
  lookups (e.g. SQL sandbox allowances) resolve inside the worker.

  Options: `:timeout_ms` (default #{5000}), `:max_heap_words` (default 50_000_000).

  ## Examples

      iex> AshR2RML.OBDA.Worker.run(fn -> 1 + 1 end)
      {:ok, 2}
  """

  alias AshR2RML.Error

  @default_timeout_ms 5000
  @default_max_heap_words 50_000_000

  @type opts :: [timeout_ms: pos_integer(), max_heap_words: pos_integer()]

  @spec run((-> term()), opts()) :: {:ok, term()} | {:error, Error.t()}
  def run(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    words = Keyword.get(opts, :max_heap_words, @default_max_heap_words)

    case validate(timeout, words) do
      :ok -> do_run(fun, timeout, words)
      {:error, _} = error -> error
    end
  end

  defp validate(timeout, words) do
    cond do
      not (is_integer(timeout) and timeout > 0) -> invalid_opt(:timeout_ms, timeout)
      not (is_integer(words) and words > 0) -> invalid_opt(:max_heap_words, words)
      true -> :ok
    end
  end

  defp invalid_opt(key, value) do
    {:error,
     Error.new(:REFUSED_INVALID_OPTION,
       message: "worker option #{key} must be a positive integer",
       details: %{option: key, value: inspect(value)}
     )}
  end

  defp do_run(fun, timeout, words) do
    parent = self()
    tag = make_ref()
    # Ash/Ecto sandbox-style ownership and telemetry lookups follow `:"$callers"`.
    callers = [parent | Process.get(:"$callers", [])]

    {pid, mref} =
      :erlang.spawn_opt(
        fn ->
          Process.put(:"$callers", callers)
          # The guardian is the worker's first act, so a worker that runs at all is guarded:
          # a caller killed before this point yields an immediate DOWN (noproc) for the monitor.
          start_guardian(parent, self())
          send(parent, {tag, execute(fun)})
        end,
        [:monitor, max_heap_size: %{size: words, kill: true, error_logger: false}]
      )

    receive do
      {^tag, {:ok, value}} ->
        Process.demonitor(mref, [:flush])
        {:ok, value}

      {^tag, {:error, kind, reason, stack}} ->
        Process.demonitor(mref, [:flush])
        {:error, crash_error(kind, reason, stack)}

      {:DOWN, ^mref, :process, ^pid, :killed} ->
        # No flush: the worker's result message, if sent, precedes its DOWN in the mailbox and
        # would have matched the clauses above first.
        {:error,
         Error.new(:REFUSED_MEMORY_LIMIT_EXCEEDED,
           message: "worker exceeded max heap of #{words} words",
           details: %{max_heap_words: words}
         )}

      {:DOWN, ^mref, :process, ^pid, reason} ->
        {:error, crash_error(:exit, reason)}
    after
      timeout ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^mref, :process, ^pid, _} -> :ok
        end

        flush(tag)

        {:error,
         Error.new(:REFUSED_QUERY_TIMEOUT,
           message: "worker exceeded timeout of #{timeout} ms",
           details: %{timeout_ms: timeout}
         )}
    end
  end

  # Owns nothing but two monitors: kills the worker if the caller dies first, exits when the
  # worker does. Unlinked from both so it never propagates exit signals.
  defp start_guardian(parent, worker) do
    spawn(fn ->
      pref = Process.monitor(parent)
      wref = Process.monitor(worker)

      receive do
        {:DOWN, ^pref, :process, _, _} -> Process.exit(worker, :kill)
        {:DOWN, ^wref, :process, _, _} -> :ok
      end
    end)

    :ok
  end

  defp execute(fun) do
    before_links = links()

    result =
      try do
        {:ok, fun.()}
      catch
        kind, reason -> {:error, kind, reason, __STACKTRACE__}
      end

    reap_links(before_links)
    result
  end

  defp links do
    {:links, links} = Process.info(self(), :links)
    links
  end

  # A linked child survives a normal worker exit; kill only processes linked to the worker
  # during the call (links present at entry are left alone; the worker is spawned unlinked).
  defp reap_links(before_links) do
    for pid <- links() -- before_links, is_pid(pid) do
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp flush(tag) do
    receive do
      {^tag, _} -> :ok
    after
      0 -> :ok
    end
  end

  defp crash_error(kind, reason, stack \\ []) do
    Error.new(:REFUSED_WORKER_CRASHED,
      message: "worker crashed (#{kind})",
      details: %{
        kind: kind,
        class: crash_class(reason),
        stacktrace: Exception.format_stacktrace(stack)
      }
    )
  end

  defp crash_class(%{__struct__: mod}), do: inspect(mod)
  defp crash_class({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp crash_class(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp crash_class(_), do: nil
end
