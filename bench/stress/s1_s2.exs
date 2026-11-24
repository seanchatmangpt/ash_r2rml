# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Stress S1/S2 (run: mix run bench/stress/s1_s2.exs). Exits 1 on any failed law.
#
#   S1 heap bomb: 10k rows x 8KB strings under Worker max_heap 2_000_000 words must refuse
#      :REFUSED_MEMORY_LIMIT_EXCEEDED, leave the caller alive, and return memory to baseline.
#   S2 row bound: 50k rows with max_rows 1_000 must refuse :REFUSED_RESULT_LIMIT_EXCEEDED
#      within 100 ms, naming the resource and the limit.
#
# Self-contained (real Ash ETS resources); no bench/support dependency.

defmodule AshR2RML.Bench.S1S2.Domain do
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.Bench.S1S2.Blob
    resource AshR2RML.Bench.S1S2.Row
  end
end

defmodule AshR2RML.Bench.S1S2.Blob do
  use Ash.Resource,
    domain: AshR2RML.Bench.S1S2.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://example.org/bench/Blob")
    subject_template("https://example.org/bench/blob/{id}")
    table_name("bench_blobs")
    attribute_mappings([{:payload, "https://example.org/bench/payload"}])
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:payload]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :payload, :string, public?: true
  end
end

defmodule AshR2RML.Bench.S1S2.Row do
  use Ash.Resource,
    domain: AshR2RML.Bench.S1S2.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("https://example.org/bench/Row")
    subject_template("https://example.org/bench/row/{id}")
    table_name("bench_rows")
    attribute_mappings([{:label, "https://example.org/bench/label"}])
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:label]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :label, :string, public?: true
  end
end

defmodule AshR2RML.Bench.S1S2 do
  alias AshR2RML.Bench.S1S2.{Blob, Domain, Row}

  @blob_rows 10_000
  @blob_bytes 8 * 1024
  @heap_words 2_000_000
  @row_rows 50_000
  @row_limit 1_000
  @s2_budget_ms 100
  @memory_slack_bytes 32 * 1024 * 1024

  def main do
    results = [s1(), s2()]

    Enum.each(results, fn {name, status, detail} -> IO.puts("#{name} #{status} #{detail}") end)

    if Enum.all?(results, &match?({_, :PASS, _}, &1)), do: :ok, else: System.halt(1)
  end

  # -- S1 ---------------------------------------------------------------------

  defp s1 do
    seed!(Blob, :payload, @blob_rows, fn i -> String.duplicate(<<rem(i, 26) + 97>>, @blob_bytes) end)
    gc_all()
    baseline = :erlang.memory(:total)
    caller = self()

    outcome =
      AshR2RML.OBDA.query(
        [Blob],
        "SELECT ?s ?p WHERE { ?s <https://example.org/bench/payload> ?p }",
        max_heap_words: @heap_words,
        timeout_ms: 60_000,
        max_rows: @blob_rows * 2
      )

    gc_all()
    after_bytes = :erlang.memory(:total)
    delta = after_bytes - baseline

    cond do
      error_code(outcome) != :REFUSED_MEMORY_LIMIT_EXCEEDED ->
        {"S1", :FAIL, "expected REFUSED_MEMORY_LIMIT_EXCEEDED, got #{inspect(outcome, limit: 5)}"}

      not Process.alive?(caller) ->
        {"S1", :FAIL, "caller died"}

      delta > @memory_slack_bytes ->
        {"S1", :FAIL, "memory not back to baseline: +#{delta} bytes (slack #{@memory_slack_bytes})"}

      true ->
        {"S1", :PASS, "refused memory limit; caller alive; memory delta #{delta} bytes"}
    end
  end

  # -- S2 ---------------------------------------------------------------------

  defp s2 do
    seed!(Row, :label, @row_rows, fn i -> "row-#{i}" end)
    gc_all()

    {us, outcome} =
      :timer.tc(fn ->
        AshR2RML.OBDA.query(
          [Row],
          "SELECT ?s ?l WHERE { ?s <https://example.org/bench/label> ?l }",
          max_rows: @row_limit
        )
      end)

    ms = us / 1000
    text = inspect(outcome, limit: :infinity, printable_limit: :infinity)

    cond do
      error_code(outcome) != :REFUSED_RESULT_LIMIT_EXCEEDED ->
        {"S2", :FAIL, "expected REFUSED_RESULT_LIMIT_EXCEEDED, got #{inspect(outcome, limit: 5)}"}

      ms > @s2_budget_ms ->
        {"S2", :FAIL, "refusal took #{Float.round(ms, 1)} ms (budget #{@s2_budget_ms})"}

      not String.contains?(text, inspect(Row)) or not String.contains?(text, Integer.to_string(@row_limit)) ->
        {"S2", :FAIL, "refusal lacks resource+limit: #{text}"}

      true ->
        {"S2", :PASS, "refused in #{Float.round(ms, 1)} ms with resource+limit"}
    end
  end

  # -- helpers ----------------------------------------------------------------

  # Accepts both envelope shapes: %AshR2RML.Error{} and %AshR2RML.Refusal{} (both carry :code).
  defp error_code({:error, %{code: code}}), do: code
  defp error_code(_), do: nil

  defp seed!(resource, field, count, value_fun) do
    inputs = for i <- 1..count, do: %{field => value_fun.(i)}

    %Ash.BulkResult{status: :success} =
      Ash.bulk_create(inputs, resource, :create,
        domain: Domain,
        authorize?: false,
        return_errors?: true,
        stop_on_error?: true
      )

    :ok
  end

  defp gc_all do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)
    :erlang.garbage_collect()
  end
end

AshR2RML.Bench.S1S2.main()
