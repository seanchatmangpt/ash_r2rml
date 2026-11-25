# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQL.Local do
  @moduledoc """
  Explicit SPARQL.ex execution against an RDF.ex data structure.

  Evaluation runs in a monitored `AshR2RML.OBDA.Worker` process capped by
  `max_heap_size` and a wall-clock timeout, so a cartesian blowup is refused
  typed instead of exhausting the caller. Only the exceptions SPARQL.ex raises
  for data or queries it cannot evaluate (`Protocol.UndefinedError`,
  `ArgumentError`, `RuntimeError`) become refusals, with the exception module
  named in the evidence; any other exception (a programmer error) propagates.
  """

  alias AshR2RML.OBDA.Worker
  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @default_timeout_ms 10_000
  @default_max_heap_words 10_000_000

  @doc """
  Options: `:max_rows` bounds the result (default 100_000), else `:REFUSED_RESOURCE_BOUND`;
  `:timeout_ms` (default #{@default_timeout_ms}) and `:max_heap_words`
  (default #{@default_max_heap_words}) bound evaluation, else `:REFUSED_RESOURCE_BOUND`.
  """
  @spec query(RDF.Data.Source.t(), String.t() | Query.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, Refusal.t()}
  def query(data, query, opts \\ []) do
    max_rows = Keyword.get(opts, :max_rows, Result.default_max_rows())

    worker_opts = [
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms),
      max_heap_words: Keyword.get(opts, :max_heap_words, @default_max_heap_words)
    ]

    with {:ok, admitted} <- Query.admit(query) do
      case Worker.call(fn -> execute(data, admitted) end, worker_opts) do
        {:ok, {:boundary_error, exception}} ->
          {:error, execution_refusal(admitted, exception)}

        {:ok, normalized} ->
          observe(admitted, normalized, max_rows)

        {:raised, kind, reason, stacktrace} ->
          :erlang.raise(kind, reason, stacktrace)

        {:error, %AshR2RML.Error{code: code, message: message}} ->
          {:error, bound_refusal(admitted, code, message)}
      end
    end
  end

  defp execute(data, admitted) do
    unless RDF.Data.Source.impl_for(data), do: raise(ArgumentError, "data has no RDF.Data implementation")

    result = Elixir.SPARQL.execute_query(data, admitted.parsed)
    normalize_local_result(admitted.form, result)
  rescue
    exception in [Protocol.UndefinedError, ArgumentError, RuntimeError] ->
      {:boundary_error, exception}
  end

  defp observe(admitted, normalized, max_rows) do
    with {:ok, result_kind, rows} <- Result.bound(normalized, :local_sparql_execution, max_rows) do
      {:ok,
       %Observation{
         strategy: :local_rdf,
         query_sha256: admitted.sha256,
         query_form: admitted.form,
         status: :PARTIAL_ALIVE,
         standing: :observed_local_rdf_execution,
         evidence_kind: :in_memory_execution,
         result_kind: result_kind,
         result_sha256: Result.hash_rows(rows),
         rows: rows,
         metadata: %{engine: :sparql_ex}
       }}
    end
  end

  defp execution_refusal(admitted, exception) do
    Refusal.new(
      :REFUSED_UNPROVEN_EQUIVALENCE,
      :local_sparql_execution,
      "SPARQL.ex could not execute the admitted query against the supplied RDF data",
      %{
        query_form: admitted.form,
        exception: Exception.message(exception),
        exception_module: inspect(exception.__struct__),
        engine_scope: :sparql_ex_local
      }
    )
  end

  defp bound_refusal(admitted, code, message) do
    Refusal.new(
      :REFUSED_RESOURCE_BOUND,
      :local_sparql_execution,
      "SPARQL.ex local evaluation exceeded its isolation bound: #{message}",
      %{query_form: admitted.form, worker_code: code, engine_scope: :sparql_ex_local}
    )
  end

  # SPARQL.ex 0.3.x represents local ASK truth as a solution sequence:
  # one empty binding for true and an empty sequence for false. Normalize that
  # engine-specific representation into the same boolean observation contract
  # used by protocol ASK results before knowledge-hook evaluation sees it.
  defp normalize_local_result(:ask, result) do
    case Result.normalize(result) do
      {:ok, :boolean, _rows} = normalized -> normalized
      {:ok, :bindings, rows} -> {:ok, :boolean, [%{"ask" => rows != []}]}
      other -> other
    end
  end

  defp normalize_local_result(_form, result), do: Result.normalize(result)
end
