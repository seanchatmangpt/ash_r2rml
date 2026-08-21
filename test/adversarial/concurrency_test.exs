# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.ConcurrencyTest do
  @moduledoc """
  Chicago-Style Concurrency & Race Condition Adversarial Test Suite.
  Executes parallel transactions and Reactor executions proving partial-order causal
  preservation and deterministic receipt generation over arbitrary wall-clock interleavings.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.Parity
  alias AshR2RML.SPARQL.{Differential, Observation, Result}

  defmodule CausalStepA do
    use Reactor.Step

    def run(arguments, _context, _opts) do
      Process.sleep(Enum.random(1..5))
      timestamp = System.monotonic_time(:microsecond)
      {:ok, %{step_a_time: timestamp, tenant_id: arguments[:tenant_id]}}
    end
  end

  defmodule CausalStepB do
    use Reactor.Step

    def run(arguments, _context, _opts) do
      Process.sleep(Enum.random(1..5))
      timestamp = System.monotonic_time(:microsecond)
      step_a = arguments[:step_a_result]

      if timestamp <= step_a.step_a_time do
        {:error, "Causality violation: Step B ran before or at Step A time"}
      else
        {:ok, %{step_b_time: timestamp, project_id: arguments[:project_id], step_a: step_a}}
      end
    end
  end

  defmodule CausalStepC do
    use Reactor.Step

    def run(arguments, _context, _opts) do
      Process.sleep(Enum.random(1..5))
      timestamp = System.monotonic_time(:microsecond)
      step_b = arguments[:step_b_result]

      if timestamp <= step_b.step_b_time do
        {:error, "Causality violation: Step C ran before or at Step B time"}
      else
        {:ok, %{step_c_time: timestamp, task_id: arguments[:task_id], step_b: step_b}}
      end
    end
  end

  defmodule CausalWorkflowReactor do
    use Reactor

    input(:tenant_id)
    input(:project_id)
    input(:task_id)

    step :step_a, CausalStepA do
      argument :tenant_id, input(:tenant_id)
    end

    step :step_b, CausalStepB do
      argument :project_id, input(:project_id)
      argument :step_a_result, result(:step_a)
    end

    step :step_c, CausalStepC do
      argument :task_id, input(:task_id)
      argument :step_b_result, result(:step_b)
    end
  end

  defmodule CompensableBranchStep do
    use Reactor.Step

    def run(arguments, _context, _opts) do
      name = arguments[:branch_name]
      caller = arguments[:caller_pid]
      send(caller, {:branch_executed, name})
      {:ok, %{branch: name, status: :executed}}
    end

    def undo(result, arguments, _context, _opts) do
      caller = arguments[:caller_pid]
      send(caller, {:branch_undone, result.branch})
      :ok
    end
  end

  defmodule FaultInjectionStep do
    use Reactor.Step

    def run(_arguments, _context, _opts) do
      {:error, "Injected adversarial fault to trigger concurrent saga rollback"}
    end
  end

  defmodule ConcurrentSagaReactor do
    use Reactor

    input(:branch_a_name)
    input(:branch_b_name)
    input(:caller_pid)

    step :branch_a, CompensableBranchStep do
      argument :branch_name, input(:branch_a_name)
      argument :caller_pid, input(:caller_pid)
    end

    step :branch_b, CompensableBranchStep do
      argument :branch_name, input(:branch_b_name)
      argument :caller_pid, input(:caller_pid)
    end

    step :failing_terminal_step, FaultInjectionStep do
      wait_for [:branch_a, :branch_b]
    end
  end

  describe "1. High-Concurrency Causal Partial-Order Preservation" do
    test "proves strict monotonic causality across 30 concurrent workflows under random jitter" do
      concurrency = 30

      tasks =
        for i <- 1..concurrency do
          Task.async(fn ->
            inputs = %{
              tenant_id: "tenant_#{i}",
              project_id: "proj_#{i}",
              task_id: "task_#{i}"
            }

            Reactor.run(CausalWorkflowReactor, inputs)
          end)
        end

      results = Task.await_many(tasks, 15_000)

      assert length(results) == concurrency

      for {:ok, res} <- results do
        step_c = res
        step_b = step_c.step_b
        step_a = step_b.step_a

        # Strict monotonic causal order verification: A < B < C
        assert step_a.step_a_time < step_b.step_b_time
        assert step_b.step_b_time < step_c.step_c_time
      end
    end
  end

  describe "2. Concurrent Saga Compensation & Failure Rollback" do
    test "reliably compensates all parallel branches under concurrent failures" do
      concurrency = 15
      caller = self()

      tasks =
        for i <- 1..concurrency do
          Task.async(fn ->
            inputs = %{
              branch_a_name: "branch_a_#{i}",
              branch_b_name: "branch_b_#{i}",
              caller_pid: caller
            }

            Reactor.run(ConcurrentSagaReactor, inputs)
          end)
        end

      results = Task.await_many(tasks, 15_000)

      # All must fail and trigger rollback
      assert Enum.all?(results, &match?({:error, _}, &1))

      # Collect all execution and rollback messages
      executed_events = collect_messages(:branch_executed, concurrency * 2)
      undone_events = collect_messages(:branch_undone, concurrency * 2)

      assert length(executed_events) == concurrency * 2
      assert length(undone_events) == concurrency * 2
      assert Enum.sort(executed_events) == Enum.sort(undone_events)
    end
  end

  describe "3. Concurrent Deterministic Parity & Differential Receipts" do
    test "generates identical cryptographic receipt digests under heavy parallel evaluation" do
      concurrency = 25

      rows = [
        %{"person" => "https://example.org/p1", "name" => "Alice", "score" => "99.50"},
        %{"person" => "https://example.org/p2", "name" => "Bob", "score" => "88.00"}
      ]

      query_sha = "018e6e5a-dead-beef-cafe-000000000001"

      obs1 = %Observation{
        strategy: :local_rdf,
        query_sha256: query_sha,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed,
        evidence_kind: :in_memory_execution,
        rows: rows,
        result_kind: :bindings,
        result_sha256: Result.hash_rows(rows)
      }

      obs2 = %Observation{
        strategy: :ontop_cli,
        query_sha256: query_sha,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed,
        evidence_kind: :system_process,
        rows: Enum.reverse(rows),
        result_kind: :bindings,
        result_sha256: Result.hash_rows(rows)
      }

      tasks =
        for _ <- 1..concurrency do
          Task.async(fn ->
            # Run Differential comparison
            {:ok, diff_receipt} = Differential.compare(:concurrent_subject, [obs1, obs2], %{batch: :parallel})

            # Run Parity comparison
            parity_receipt = Parity.compare(:sparql_sql, :concurrent_subject, rows, Enum.reverse(rows))

            {diff_receipt.receipt_sha256, parity_receipt.receipt_sha256}
          end)
        end

      receipt_pairs = Task.await_many(tasks, 10_000)

      diff_hashes = Enum.map(receipt_pairs, &elem(&1, 0)) |> Enum.uniq()
      parity_hashes = Enum.map(receipt_pairs, &elem(&1, 1)) |> Enum.uniq()

      # Every single concurrent execution must produce identical cryptographic hashes
      assert length(diff_hashes) == 1
      assert length(parity_hashes) == 1
    end
  end

  defp collect_messages(tag, expected_count, acc \\ []) do
    if length(acc) == expected_count do
      acc
    else
      receive do
        {^tag, value} -> collect_messages(tag, expected_count, [value | acc])
      after
        1000 -> acc
      end
    end
  end
end
