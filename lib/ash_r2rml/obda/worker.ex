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

  Options: `:timeout_ms` (default 5000), `:max_heap_words` (default 10_000_000).

  ## Concurrency bound

  At most `max_concurrent/0` workers run at once node-wide (application env
  `:ash_r2rml, :max_obda_workers`, default `min(max(4 * schedulers, 16), 32)`). A call over the
  bound is refused at once with `:REFUSED_RESOURCE_BOUND` and spawns nothing. Admission is a
  lock-free compare-and-swap on an `:atomics` slot, so exactly `max_concurrent/0` callers of a
  burst are admitted. The guardian process acquires the slot and releases it once the worker is
  gone, so a killed caller, a timeout or a heap kill frees it.

  ## Message protocol

  Guardian to caller: `{tag, reply}` where `tag` is a fresh reference and `reply` is `:full`,
  `:timeout`, `{:result, outcome}` or `{:down, reason}`. On timeout the caller sends
  `{:timeout, tag}` to the guardian, which kills the worker, waits for its DOWN, and replies.

  ## Lifecycle: who dies when

    * Caller dies: the guardian sees the caller's DOWN, kills the worker and releases the slot.
    * Worker finishes or crashes: the guardian receives the result or DOWN, releases the slot,
      replies and exits. Links the worker opened during the call are killed on a normal return.
    * Timeout: the guardian kills the worker, waits for its DOWN, releases and replies.
    * Guardian is killed externally: the link takes the worker down with it (fail-closed).
    * Neither guardian nor worker is linked to the caller, so no failure inside them can kill
      the caller.

  `call/2` is `run/2` without the crash mapping: an exception raised by `fun` comes back as
  `{:raised, kind, reason, stacktrace}` so the caller can classify the real reason.

  ## Examples

      iex> AshR2RML.OBDA.Worker.run(fn -> 1 + 1 end)
      {:ok, 2}
  """

  alias AshR2RML.Error

  @default_timeout_ms 5000
  @default_max_heap_words 10_000_000
  @gate_key {__MODULE__, :gate}
  @cas_key {__MODULE__, :cas}

  @type opts :: [timeout_ms: pos_integer(), max_heap_words: pos_integer()]

  @doc """
  Runs `fun` in a bounded worker and returns `{:ok, value}`. Never raises: a raise, throw or
  exit inside `fun`, a timeout, a heap breach and an invalid option are all returned as
  `{:error, %AshR2RML.Error{}}` (see the moduledoc for the codes).
  """
  @spec run((-> term()), opts()) :: {:ok, term()} | {:error, Error.t()}
  def run(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    case call(fun, opts) do
      {:raised, kind, reason, stack} -> {:error, crash_error(kind, reason, stack)}
      outcome -> outcome
    end
  end

  @doc """
  Like `run/2`, but a raise/throw/exit inside `fun` is returned as
  `{:raised, kind, reason, stacktrace}` with the original reason intact, so the caller can
  classify the real exception instead of the generic `:REFUSED_WORKER_CRASHED`. Bound
  violations and abnormal worker death are still typed `{:error, %AshR2RML.Error{}}`.
  """
  @spec call((-> term()), opts()) ::
          {:ok, term()}
          | {:error, Error.t()}
          | {:raised, :error | :exit | :throw, term(), Exception.stacktrace()}
  def call(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
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
    # The guardian acquires the slot, runs the worker and releases the slot, all on the caller's
    # behalf, so a caller killed at any point cannot leak the slot or orphan the worker.
    tag = make_ref()
    {guardian, gref} = start_guardian(self(), fun, words, tag)

    receive do
      {^tag, reply} ->
        Process.demonitor(gref, [:flush])
        reply_outcome(reply, timeout, words)

      {:DOWN, ^gref, :process, ^guardian, reason} ->
        {:error, crash_error(:exit, reason)}
    after
      timeout ->
        send(guardian, {:timeout, tag})

        receive do
          {^tag, reply} ->
            Process.demonitor(gref, [:flush])
            reply_outcome(reply, timeout, words)

          {:DOWN, ^gref, :process, ^guardian, reason} ->
            {:error, crash_error(:exit, reason)}
        end
    end
  end

  defp reply_outcome(:full, _timeout, _words) do
    {:error,
     Error.new(:REFUSED_RESOURCE_BOUND,
       message: "OBDA worker concurrency bound reached (#{max_concurrent()})",
       details: %{max_concurrent_workers: max_concurrent()}
     )}
  end

  defp reply_outcome({:result, {:ok, value}}, _timeout, _words), do: {:ok, value}

  defp reply_outcome({:result, {:error, kind, reason, stack}}, _timeout, _words),
    do: {:raised, kind, reason, stack}

  # The runtime reports a max_heap_size kill and an untrappable :kill identically.
  defp reply_outcome({:down, :killed}, _timeout, words) do
    {:error,
     Error.new(:REFUSED_MEMORY_LIMIT_EXCEEDED,
       message: "worker exceeded max heap of #{words} words",
       details: %{max_heap_words: words}
     )}
  end

  defp reply_outcome({:down, reason}, _timeout, _words),
    do: {:error, crash_error(:exit, reason)}

  defp reply_outcome(:timeout, timeout, _words) do
    {:error,
     Error.new(:REFUSED_QUERY_TIMEOUT,
       message: "worker exceeded timeout of #{timeout} ms",
       details: %{timeout_ms: timeout}
     )}
  end

  @doc "Node-wide bound on concurrently running OBDA workers."
  @spec max_concurrent() :: pos_integer()
  def max_concurrent do
    case Application.get_env(:ash_r2rml, :max_obda_workers) do
      n when is_integer(n) and n > 0 -> n
      _ -> min(max(4 * System.schedulers_online(), 16), 32)
    end
  end

  # Shared gate state, created once under a global lock so concurrent first callers agree:
  # an `:atomics` slot decides admission by CAS, and a `:counters` mirror exposes the live
  # in-flight count as an observable.
  defp gate do
    case :persistent_term.get(@cas_key, nil) do
      nil ->
        :global.trans({@gate_key, self()}, fn ->
          case :persistent_term.get(@cas_key, nil) do
            nil ->
              :persistent_term.put(@gate_key, :counters.new(1, [:atomics]))
              slots = :atomics.new(1, [])
              :persistent_term.put(@cas_key, slots)
              slots

            slots ->
              slots
          end
        end)

      slots ->
        slots
    end
  end

  # Lock-free admission: CAS the in-flight count from n to n + 1 only while n < max, so
  # exactly `max_concurrent/0` callers win a burst and no caller is refused spuriously.
  defp acquire do
    slots = gate()
    counter = :persistent_term.get(@gate_key)

    if cas_admit(slots, max_concurrent()) do
      :counters.add(counter, 1, 1)
      {:ok, {slots, counter}}
    else
      :full
    end
  end

  defp cas_admit(slots, max) do
    current = :atomics.get(slots, 1)

    cond do
      current >= max -> false
      :atomics.compare_exchange(slots, 1, current, current + 1) == :ok -> true
      true -> cas_admit(slots, max)
    end
  end

  defp release({slots, counter}) do
    :counters.sub(counter, 1, 1)
    :atomics.sub(slots, 1, 1)
    :ok
  end

  # The guardian is spawned unlinked from the caller (so nothing in it can kill the caller) and
  # monitored by it. It traps exits because the worker is linked to it: a guardian killed from
  # outside takes the worker down (fail-closed), while a worker death never kills the guardian.
  defp start_guardian(parent, fun, words, tag) do
    callers = [parent | Process.get(:"$callers", [])]
    :erlang.spawn_opt(fn -> guardian(parent, fun, words, tag, callers) end, [:monitor])
  end

  defp guardian(parent, fun, words, tag, callers) do
    Process.flag(:trap_exit, true)
    pref = Process.monitor(parent)

    case acquire() do
      :full ->
        send(parent, {tag, :full})

      {:ok, gate_ref} ->
        guardian = self()

        {worker, wref} =
          :erlang.spawn_opt(
            fn ->
              Process.put(:"$callers", callers)
              send(guardian, {tag, execute(fun)})
            end,
            [
              :monitor,
              :link,
              max_heap_size: %{size: words, kill: true, error_logger: false}
            ]
          )

        outcome = supervise(worker, wref, pref, tag)
        release(gate_ref)
        if outcome != :caller_gone, do: send(parent, {tag, outcome})
    end

    :ok
  end

  # Exactly one event decides the outcome. A result precedes the worker's own DOWN in the
  # mailbox, so it always wins over it.
  defp supervise(worker, wref, pref, tag) do
    receive do
      {^tag, result} ->
        Process.demonitor(wref, [:flush])
        {:result, result}

      {:DOWN, ^wref, :process, ^worker, reason} ->
        {:down, reason}

      {:DOWN, ^pref, :process, _, _} ->
        kill_and_reap(worker, wref)
        :caller_gone

      {:timeout, ^tag} ->
        kill_and_reap(worker, wref)
        :timeout
    end
  end

  # Kill, then wait for the DOWN so the slot is only freed once the worker is really gone.
  defp kill_and_reap(worker, wref) do
    Process.exit(worker, :kill)

    receive do
      {:DOWN, ^wref, :process, ^worker, _} -> :ok
    end
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
