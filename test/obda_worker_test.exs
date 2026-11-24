# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.WorkerTest do
  use ExUnit.Case, async: true

  alias AshR2RML.OBDA.Worker

  doctest AshR2RML.OBDA.Worker

  defp code({:error, %{code: code}}), do: code

  test "returns the value of a healthy function" do
    assert {:ok, [1, 2, 3]} = Worker.run(fn -> Enum.to_list(1..3) end)
  end

  test "infinite receive is killed at the timeout" do
    result = Worker.run(fn -> receive do: (:never -> :ok) end, timeout_ms: 20)
    assert code(result) == :REFUSED_QUERY_TIMEOUT
  end

  test "heap hog is killed by max_heap_size" do
    hog = fn ->
      Enum.reduce(1..10_000_000, [], fn i, acc -> [i | acc] end)
    end

    result = Worker.run(hog, max_heap_words: 100_000, timeout_ms: 10_000)
    assert code(result) == :REFUSED_MEMORY_LIMIT_EXCEEDED
  end

  test "raise, throw and exit become typed errors without raising" do
    for f <- [fn -> raise "boom" end, fn -> throw(:x) end, fn -> exit(:bye) end] do
      assert code(Worker.run(f)) == :REFUSED_WORKER_CRASHED
    end
  end

  test "caller mailbox is clean afterwards" do
    Worker.run(fn -> :ok end)
    Worker.run(fn -> receive do: (:never -> :ok) end, timeout_ms: 10)
    refute_received _
  end
end
