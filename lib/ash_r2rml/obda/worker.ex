# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Worker do
  @moduledoc """
  Bounded, stateless worker isolation for OBDA query evaluation.

  `run/2` executes a zero-arity function in a monitored process capped by
  `max_heap_size` (kill on breach) and a wall-clock timeout. It never raises:
  every failure is returned as `{:error, %AshR2RML.Error{}}` with one of
  `:REFUSED_QUERY_TIMEOUT`, `:REFUSED_MEMORY_LIMIT_EXCEEDED`, or
  `:REFUSED_WORKER_CRASHED`.

  A bare `:killed` exit of the worker is attributed to the heap cap: the runtime reports a
  `max_heap_size` kill and an untrappable `:kill` signal identically. Any other exit reason
  is a `:REFUSED_WORKER_CRASHED` with `details.kind == :exit`.

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
    parent = self()
    tag = make_ref()

    {pid, mref} =
      :erlang.spawn_opt(
        fn -> send(parent, {tag, execute(fun)}) end,
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
        flush(tag)

        {:error,
         Error.new(:REFUSED_MEMORY_LIMIT_EXCEEDED,
           message: "worker exceeded max heap of #{words} words",
           details: %{max_heap_words: words}
         )}

      {:DOWN, ^mref, :process, ^pid, reason} ->
        flush(tag)
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

  defp execute(fun) do
    result =
      try do
        {:ok, fun.()}
      catch
        kind, reason -> {:error, kind, reason, __STACKTRACE__}
      end

    reap_links()

    case result do
      {:error, kind, reason, stack} -> {:error, kind, reason, stack}
      ok -> ok
    end
  end

  # A linked child survives a normal worker exit; kill every process still linked to the
  # worker (never the caller: the worker is spawned unlinked) so none leak past the call.
  defp reap_links do
    {:links, links} = Process.info(self(), :links)

    for pid <- links, is_pid(pid) do
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
