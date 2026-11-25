# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Red2WorkerGateTest do
  @moduledoc """
  Red-before-green: the OBDA worker concurrency gate must admit exactly `max_concurrent/0`
  callers under a burst (no spurious refusals from add-then-get), and every slot must return to
  the counter however the caller or worker ends.
  """

  use ExUnit.Case, async: false

  alias AshR2RML.Error
  alias AshR2RML.OBDA.Worker

  @limit 4
  @callers 64
  @rounds 30

  setup do
    previous = Application.fetch_env(:ash_r2rml, :max_obda_workers)
    Application.put_env(:ash_r2rml, :max_obda_workers, @limit)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:ash_r2rml, :max_obda_workers, value)
        :error -> Application.delete_env(:ash_r2rml, :max_obda_workers)
      end
    end)

    # Prime the gate so the counter exists, then require a clean baseline.
    assert {:ok, :primed} = Worker.call(fn -> :primed end)
    assert :ok = await_counter_zero()
    :ok
  end

  # The single audited poll: bounded by a monotonic deadline.
  defp await_counter_zero do
    deadline = System.monotonic_time(:millisecond) + 10_000
    poll_counter(deadline)
  end

  defp poll_counter(deadline) do
    cond do
      counter_value() == 0 ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        {:error, {:counter_stuck, counter_value()}}

      true ->
        receive do
        after
          2 -> poll_counter(deadline)
        end
    end
  end

  defp counter_value do
    :counters.get(:persistent_term.get({Worker, :gate}), 1)
  end

  defp collect(0, acc), do: acc

  defp collect(n, acc) do
    receive do
      {:admitted, pid} -> collect(n - 1, %{acc | admitted: [pid | acc.admitted]})
      {:rejected, _} -> collect(n - 1, %{acc | rejected: acc.rejected + 1})
    after
      15_000 -> flunk("burst did not settle, missing #{n} callers")
    end
  end

  defp burst_round(test_pid) do
    callers =
      for _ <- 1..@callers do
        spawn(fn ->
          receive do
            :go -> :ok
          end

          result =
            Worker.call(
              fn ->
                send(test_pid, {:admitted, self()})

                receive do
                  :release -> :ok
                after
                  20_000 -> :gave_up
                end
              end,
              timeout_ms: 30_000
            )

          case result do
            {:error, %Error{} = e} -> send(test_pid, {:rejected, e})
            other -> send(test_pid, {:done, other})
          end
        end)
      end

    Enum.each(callers, &send(&1, :go))
    outcome = collect(@callers, %{admitted: [], rejected: 0})
    Enum.each(outcome.admitted, &send(&1, :release))
    outcome
  end

  describe "gate admission" do
    test "a burst admits exactly max_concurrent callers and the counter returns to 0" do
      test_pid = self()

      for round <- 1..@rounds do
        outcome = burst_round(test_pid)

        assert length(outcome.admitted) == @limit,
               "round #{round}: admitted #{length(outcome.admitted)} of #{@limit}"

        assert outcome.rejected == @callers - @limit
        assert :ok = await_counter_zero()
      end
    end

    test "a burst of exactly max_concurrent callers admits all of them" do
      test_pid = self()

      pids =
        for _ <- 1..@limit do
          spawn(fn ->
            Worker.call(
              fn ->
                send(test_pid, {:admitted, self()})

                receive do
                  :release -> :ok
                after
                  20_000 -> :gave_up
                end
              end,
              timeout_ms: 30_000
            )
          end)
        end

      outcome = collect(@limit, %{admitted: [], rejected: 0})
      Enum.each(outcome.admitted, &send(&1, :release))

      assert length(outcome.admitted) == @limit
      assert Enum.all?(pids, &is_pid/1)
      assert :ok = await_counter_zero()
    end
  end

  describe "slot leak regressions" do
    test "a caller killed while its worker runs frees the slot" do
      test_pid = self()

      caller =
        spawn(fn ->
          Worker.call(
            fn ->
              send(test_pid, {:in_worker, self()})

              receive do
                :never -> :ok
              after
                20_000 -> :gave_up
              end
            end,
            timeout_ms: 30_000
          )
        end)

      assert_receive {:in_worker, _worker}, 10_000
      assert counter_value() == 1

      Process.exit(caller, :kill)
      assert :ok = await_counter_zero()
    end

    test "callers killed immediately after acquire never leak a slot" do
      test_pid = self()

      for _ <- 1..300 do
        caller =
          spawn(fn ->
            Worker.call(
              fn ->
                send(test_pid, {:in_worker, self()})

                receive do
                  :never -> :ok
                after
                  20_000 -> :gave_up
                end
              end,
              timeout_ms: 30_000
            )
          end)

        Process.exit(caller, :kill)
      end

      assert :ok = await_counter_zero()
    end

    test "a worker killed by the heap cap frees the slot" do
      result =
        Worker.call(fn -> Enum.to_list(1..5_000_000) end, max_heap_words: 50_000)

      assert {:error, %Error{}} = result
      assert :ok = await_counter_zero()
    end

    test "a worker that times out frees the slot" do
      result =
        Worker.call(
          fn ->
            receive do
              :never -> :ok
            end
          end,
          timeout_ms: 50
        )

      assert {:error, %Error{}} = result
      assert :ok = await_counter_zero()
    end

    test "a worker that raises frees the slot" do
      assert {:error, %Error{}} = Worker.run(fn -> raise "boom" end)
      assert :ok = await_counter_zero()
    end
  end
end
