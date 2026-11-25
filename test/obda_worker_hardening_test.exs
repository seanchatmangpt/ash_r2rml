# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDAWorkerHardeningTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Error
  alias AshR2RML.OBDA.Worker

  defp eventually(fun, budget_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    do_eventually(fun, deadline)
  end

  defp do_eventually(fun, deadline) do
    case fun.() do
      true ->
        true

      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          false
        else
          receive do
          after
            5 -> :ok
          end

          do_eventually(fun, deadline)
        end
    end
  end

  defp mailbox, do: Process.info(self(), :messages) |> elem(1)

  defp crashed(fun, opts \\ []) do
    assert {:error, %Error{code: :REFUSED_WORKER_CRASHED} = e} = Worker.run(fun, opts)
    e
  end

  test "raise is returned with class and reason in details" do
    e = crashed(fn -> raise ArgumentError, "boom" end)
    assert e.details.kind == :error
    assert e.details.raw_reason == %ArgumentError{message: "boom"}
    assert e.details.stacktrace =~ "OBDAWorkerHardeningTest"
  end

  test "exit, throw and badarg are typed" do
    assert crashed(fn -> exit({:aborted, :mnesia}) end).details.raw_reason == {:aborted, :mnesia}
    assert crashed(fn -> exit({:aborted, :mnesia}) end).details.kind == :exit
    e = crashed(fn -> throw(:ball) end)
    assert {e.details.kind, e.details.raw_reason} == {:throw, :ball}
    e = crashed(fn -> :erlang.binary_to_atom(1, :utf8) end)
    assert {e.details.kind, e.details.raw_reason} == {:error, :badarg}
  end

  test "exit(:killed) inside fun is a crash, not a memory refusal" do
    e = crashed(fn -> exit(:killed) end)
    assert e.details.raw_reason == :killed
  end

  test "externally killed worker is typed" do
    # A `:kill` signal is indistinguishable from a max_heap_size kill (both DOWN :killed), so
    # the external-termination premise is pinned with a catchable-by-runtime non-kill reason.
    e = crashed(fn -> Process.exit(self(), :shutdown) end)
    assert e.details.kind == :exit
    assert e.details.raw_reason == :shutdown
  end

  test "timeout and heap refusals still typed" do
    assert {:error, %Error{code: :REFUSED_QUERY_TIMEOUT}} =
             Worker.run(fn -> Process.sleep(:infinity) end, timeout_ms: 50)

    assert {:error, %Error{code: :REFUSED_MEMORY_LIMIT_EXCEEDED}} =
             Worker.run(fn -> Enum.to_list(1..5_000_000) |> length() end,
               max_heap_words: 100_000,
               timeout_ms: 5_000
             )
  end

  test "linked child is reaped after normal return and after raise" do
    parent = self()

    for fun <- [
          fn ->
            send(parent, {:child, spawn_link(fn -> Process.sleep(:infinity) end)})
            :done
          end,
          fn ->
            send(parent, {:child, spawn_link(fn -> Process.sleep(:infinity) end)})
            raise "after spawn"
          end
        ] do
      Worker.run(fun)
      assert_receive {:child, child}
      assert eventually(fn -> not Process.alive?(child) end)
    end
  end

  test "caller mailbox is clean after every outcome" do
    Worker.run(fn -> 1 end)
    crashed(fn -> raise "x" end)
    crashed(fn -> exit(:x) end)
    Worker.run(fn -> Process.sleep(:infinity) end, timeout_ms: 30)
    Worker.run(fn -> Enum.to_list(1..2_000_000) end, max_heap_words: 50_000)
    assert eventually(fn -> mailbox() == [] end)
  end

  test "caller trapping exits receives no EXIT messages and survives" do
    task =
      Task.async(fn ->
        Process.flag(:trap_exit, true)
        r1 = Worker.run(fn -> raise "x" end)
        r2 = Worker.run(fn -> spawn_link(fn -> exit(:child_died) end) && Process.sleep(100) end)
        r3 = Worker.run(fn -> 7 end)
        {r1, r2, r3, Process.info(self(), :messages) |> elem(1)}
      end)

    {r1, r2, r3, msgs} = Task.await(task, 5_000)
    assert {:error, %Error{code: :REFUSED_WORKER_CRASHED}} = r1
    assert {:error, %Error{code: :REFUSED_WORKER_CRASHED}} = r2
    assert r3 == {:ok, 7}
    assert msgs == []
  end

  test "process count returns to baseline after many failing runs" do
    parent = self()

    for _ <- 1..50 do
      Worker.run(fn ->
        send(parent, {:leaf, spawn_link(fn -> Process.sleep(:infinity) end)})
        raise "leak?"
      end)
    end

    leaves =
      for _ <- 1..50,
          do:
            (receive do
               {:leaf, pid} -> pid
             end)

    assert length(Enum.uniq(leaves)) == 50
    assert eventually(fn -> Enum.all?(leaves, &(not Process.alive?(&1))) end)
  end
end
