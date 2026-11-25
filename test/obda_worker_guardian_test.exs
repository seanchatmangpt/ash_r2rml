# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAWorkerGuardianTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Error
  alias AshR2RML.OBDA.Worker

  @deadline 2_000

  defp down?(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> true
    after
      @deadline -> false
    end
  end

  # Bounded poll: the guardian is spawned by the worker, so it may not have monitored yet.
  defp await_guardian(worker, known, deadline) do
    {:monitored_by, watchers} = Process.info(worker, :monitored_by)

    case watchers -- known do
      [guardian] ->
        guardian

      other ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("expected exactly one guardian watching the worker, got #{inspect(other)}")
        else
          # SLEEP-CLASS: POLL-STEP
          receive do
          after
            2 -> await_guardian(worker, known, deadline)
          end
        end
    end
  end

  test "killing the caller reaps the worker" do
    test_pid = self()

    {caller, cref} =
      spawn_monitor(fn ->
        Worker.run(
          fn ->
            send(test_pid, {:worker, self()})
            Process.sleep(:infinity)
          end,
          timeout_ms: 60_000
        )
      end)

    assert_receive {:worker, worker}, @deadline
    assert Process.alive?(worker)

    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^cref, :process, ^caller, :killed}, @deadline
    assert down?(worker)
  end

  test "killing the outer worker reaps a nested worker" do
    test_pid = self()

    {caller, _cref} =
      spawn_monitor(fn ->
        Worker.run(
          fn ->
            send(test_pid, {:outer, self()})

            Worker.run(
              fn ->
                send(test_pid, {:inner, self()})
                Process.sleep(:infinity)
              end,
              timeout_ms: 60_000
            )
          end,
          timeout_ms: 60_000
        )
      end)

    assert_receive {:outer, outer}, @deadline
    assert_receive {:inner, inner}, @deadline

    Process.exit(outer, :kill)
    assert down?(inner)
    assert down?(outer)
    Process.exit(caller, :kill)
  end

  test "killing the caller reaps outer and nested workers" do
    test_pid = self()

    {caller, _cref} =
      spawn_monitor(fn ->
        Worker.run(
          fn ->
            send(test_pid, {:outer, self()})

            Worker.run(
              fn ->
                send(test_pid, {:inner, self()})
                Process.sleep(:infinity)
              end,
              timeout_ms: 60_000
            )
          end,
          timeout_ms: 60_000
        )
      end)

    assert_receive {:outer, outer}, @deadline
    assert_receive {:inner, inner}, @deadline
    Process.exit(caller, :kill)
    assert down?(outer)
    assert down?(inner)
  end

  test "guardian exits when the worker finishes" do
    test_pid = self()

    task =
      Task.async(fn ->
        Worker.run(fn ->
          send(test_pid, {:worker, self()})

          receive do
            :go -> :done
          end
        end)
      end)

    assert_receive {:worker, worker}, @deadline
    guardian = await_guardian(worker, [task.pid, test_pid], System.monotonic_time(:millisecond) + @deadline)
    assert is_pid(guardian)

    send(worker, :go)
    assert {:ok, :done} = Task.await(task, @deadline)
    assert down?(guardian)
  end

  test "invalid options return a typed error instead of raising" do
    for opts <- [
          [timeout_ms: 0],
          [timeout_ms: -1],
          [timeout_ms: "5"],
          [timeout_ms: nil],
          [max_heap_words: 0],
          [max_heap_words: 1.5],
          [max_heap_words: :big]
        ] do
      assert {:error, %Error{code: :REFUSED_INVALID_OPTION}} = Worker.run(fn -> 1 end, opts)
    end

    assert {:ok, 1} = Worker.run(fn -> 1 end, timeout_ms: 1_000, max_heap_words: 1_000_000)
  end

  test "a process linked during the call is reaped" do
    test_pid = self()
    {bystander, bref} = spawn_monitor(fn -> Process.sleep(:infinity) end)

    Worker.run(fn ->
      Process.link(bystander)
      send(test_pid, :linked)
      :ok
    end)

    assert_receive :linked, @deadline
    assert_receive {:DOWN, ^bref, :process, ^bystander, _}, @deadline
  end
end
