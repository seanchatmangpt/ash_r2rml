defmodule AshR2RML.SPARQL.Local do
  @moduledoc "Explicit SPARQL.ex execution against an RDF.ex data structure."

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @doc "Option `:max_rows` bounds the result (default 100_000), else `:REFUSED_RESOURCE_BOUND`."
  @spec query(RDF.Data.Source.t(), String.t() | Query.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, Refusal.t()}
  def query(data, query, opts \\ []) do
    max_rows = Keyword.get(opts, :max_rows, Result.default_max_rows())

    with {:ok, admitted} <- Query.admit(query) do
      try do
        result = Elixir.SPARQL.execute_query(data, admitted.parsed)

        with {:ok, result_kind, rows} <-
               admitted.form
               |> normalize_local_result(result)
               |> Result.bound(:local_sparql_execution, max_rows) do
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
      rescue
        exception ->
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :local_sparql_execution,
             "SPARQL.ex could not execute the admitted query against the supplied RDF data",
             %{
               query_form: admitted.form,
               exception: Exception.message(exception),
               engine_scope: :sparql_ex_local
             }
           )}
      end
    end
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
