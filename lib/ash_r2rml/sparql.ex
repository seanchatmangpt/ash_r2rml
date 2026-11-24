# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQL.Query do
  @moduledoc """
  Admitted SPARQL query identity.

  Parsing is delegated to SPARQL.ex. The receipt identity covers the exact
  lexical query supplied by the caller; it is not a claim of canonical SPARQL
  algebra equivalence.
  """

  alias AshR2RML.Refusal

  @enforce_keys [:source, :parsed, :form, :sha256]
  defstruct [:source, :parsed, :form, :sha256]

  @type t :: %__MODULE__{
          source: String.t(),
          parsed: Elixir.SPARQL.Query.t(),
          form: atom(),
          sha256: String.t()
        }

  @spec load_file(String.t(), keyword()) :: {:ok, t()} | {:error, Refusal.t()}
  def load_file(file_path, _opts \\ []) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        admit(content)

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_query,
           "failed to read SPARQL file from disk: #{inspect(reason)}",
           %{path: file_path}
         )}
    end
  end

  @spec admit(t() | String.t() | Elixir.SPARQL.Query.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def admit(%__MODULE__{} = admitted), do: {:ok, admitted}

  def admit(%Elixir.SPARQL.Query{query_string: source} = parsed) when is_binary(source) do
    {:ok,
     %__MODULE__{
       source: source,
       parsed: parsed,
       form: parsed.form,
       sha256: sha256(source)
     }}
  end

  def admit(source) when is_binary(source) do
    try do
      case Elixir.SPARQL.Query.new(source, default_prefixes: nil) do
        %Elixir.SPARQL.Query{} = parsed ->
          admit(parsed, source)

        {:error, reason} ->
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :sparql_query,
             "SPARQL.ex refused the query during language admission",
             %{reason: inspect(reason)}
           )}
      end
    rescue
      exception ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_query,
           "SPARQL.ex raised during language admission",
           %{reason: Exception.message(exception)}
         )}
    end
  end

  def admit(other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_query,
       "expected SPARQL query text or SPARQL.Query",
       %{got: inspect(other)}
     )}
  end

  def admit(%Elixir.SPARQL.Query{} = parsed, source) when is_binary(source) do
    {:ok,
     %__MODULE__{
       source: source,
       parsed: parsed,
       form: parsed.form,
       sha256: sha256(source)
     }}
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

defmodule AshR2RML.SPARQL.Observation do
  @moduledoc "Evidence-bounded observation from one selected SPARQL execution strategy."

  @enforce_keys [:strategy, :query_sha256, :query_form, :status, :standing, :evidence_kind, :rows]
  defstruct [
    :strategy,
    :query_sha256,
    :query_form,
    :status,
    :standing,
    :evidence_kind,
    :endpoint,
    :result_kind,
    :result_sha256,
    rows: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          strategy: :local_rdf | :protocol,
          query_sha256: String.t(),
          query_form: atom(),
          status: atom(),
          standing: atom(),
          evidence_kind: atom(),
          endpoint: String.t() | nil,
          result_kind: atom() | nil,
          result_sha256: String.t() | nil,
          rows: list(),
          metadata: map()
        }
end

defmodule AshR2RML.SPARQL.Result do
  @moduledoc "Normalizes RDF-Elixir SPARQL results into deterministic parity rows."

  alias AshR2RML.Refusal

  @spec normalize(term()) :: {:ok, atom(), list()} | {:error, Refusal.t()}
  def normalize(%Elixir.SPARQL.Query.Result{results: results}) when is_list(results) do
    {:ok, :bindings, Enum.map(results, &normalize_binding/1)}
  end

  def normalize(%Elixir.SPARQL.Query.Result{results: result}) when is_boolean(result) do
    {:ok, :boolean, [%{"ask" => result}]}
  end

  def normalize(data) do
    try do
      rows = data |> RDF.Data.statements() |> Enum.map(&normalize_statement/1)
      {:ok, :rdf, rows}
    rescue
      _ ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_result,
           "unsupported SPARQL result shape",
           %{result: inspect(data)}
         )}
    end
  end

  @spec hash_rows(list()) :: String.t()
  def hash_rows(rows) do
    rows
    |> AshR2RML.Parity.normalize_multiset()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_binding(binding) when is_map(binding) do
    Map.new(binding, fn {key, value} -> {normalize_var_name(key), normalize_term(value)} end)
  end

  defp normalize_var_name(%{name: name}), do: to_string(name)
  defp normalize_var_name(key) when is_atom(key), do: Atom.to_string(key) |> String.trim_leading("?")
  defp normalize_var_name(key) when is_binary(key), do: String.trim_leading(key, "?")
  defp normalize_var_name(other), do: other |> to_string() |> String.trim_leading("?")

  defp normalize_statement({subject, predicate, object}) do
    %{
      "subject" => normalize_term(subject),
      "predicate" => normalize_term(predicate),
      "object" => normalize_term(object)
    }
  end

  defp normalize_statement({subject, predicate, object, graph_name}) do
    %{
      "subject" => normalize_term(subject),
      "predicate" => normalize_term(predicate),
      "object" => normalize_term(object),
      "graph" => normalize_term(graph_name)
    }
  end

  defp normalize_term(nil), do: nil

  # xsd:decimal (and other arbitrary-precision numeric datatypes) have an XSD
  # *value space* that ignores trailing zeros ("45.50" == "45.5"), so
  # `RDF.Term.value/1` legitimately collapses "45.50" to `Decimal.new("45.5")`.
  # An external OBDA engine emits the database's raw lexical numeric
  # string over CSV with no datatype tag and no value-space reduction — a
  # `NUMERIC(6,2)` column round-trips as the literal text "45.50". Comparing
  # the local engine's value-space-reduced Decimal against the engine's untouched
  # lexical string byte-for-bit was producing spurious parity mismatches
  # (`receipt.verified? == false`) for any decimal literal with a lexical
  # scale not preserved by its numeric value (observed: xsd:decimal "45.50",
  # "30.00", "50000.00" all reduced to "45.5"/"30"/"50000" locally while the engine
  # kept the ".50"/".00" trailing zeros). Preserve the original lexical form
  # for decimal literals so both engines are compared on the same text this
  # relational/RDF round-trip actually produces.
  defp normalize_term(%RDF.Literal{} = literal) do
    if RDF.Literal.datatype_id(literal) == RDF.NS.XSD.decimal() do
      RDF.Literal.lexical(literal)
    else
      normalize_rdf_value(literal)
    end
  end

  defp normalize_term(value), do: normalize_rdf_value(value)

  defp normalize_rdf_value(value) do
    if RDF.Term.term?(value), do: RDF.Term.value(value), else: value
  rescue
    _ -> value
  end
end

defmodule AshR2RML.SPARQL.Local do
  @moduledoc "Explicit SPARQL.ex execution against an RDF.ex data structure."

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @spec query(RDF.Data.Source.t(), String.t() | Query.t()) ::
          {:ok, Observation.t()} | {:error, Refusal.t()}
  def query(data, query) do
    with {:ok, admitted} <- Query.admit(query) do
      try do
        result = Elixir.SPARQL.execute_query(data, admitted.parsed)

        with {:ok, result_kind, rows} <- normalize_local_result(admitted.form, result) do
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

defmodule AshR2RML.SPARQL.Protocol do
  @moduledoc """
  Read-only W3C SPARQL Protocol execution through SPARQL.Client.

  SPARQL.Client also implements update operations, but this module deliberately
  exposes queries only. Verification capability never manufactures remote
  mutation authority.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @spec query(String.t(), String.t() | Query.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, term()}
  def query(endpoint, query, opts \\ []) when is_binary(endpoint) do
    do_query(
      endpoint,
      query,
      opts,
      &Elixir.SPARQL.Client.query/3,
      :sparql_protocol,
      :observed_remote_query
    )
  end

  @doc "Injected client path for deterministic unit tests. Never a remote-query witness."
  @spec query_with(String.t(), String.t() | Query.t(), keyword(), function()) ::
          {:ok, Observation.t()} | {:error, term()}
  def query_with(endpoint, query, opts, client_fun)
      when is_binary(endpoint) and is_function(client_fun, 3) do
    do_query(endpoint, query, opts, client_fun, :injected_client, :test_double_only)
  end

  defp do_query(endpoint, query, opts, client_fun, evidence_kind, standing) do
    with {:ok, admitted} <- Query.admit(query),
         {:ok, result} <- client_fun.(admitted.parsed, endpoint, opts),
         {:ok, result_kind, rows} <- Result.normalize(result) do
      {:ok,
       %Observation{
         strategy: :protocol,
         query_sha256: admitted.sha256,
         query_form: admitted.form,
         status: :PARTIAL_ALIVE,
         standing: standing,
         evidence_kind: evidence_kind,
         endpoint: endpoint,
         result_kind: result_kind,
         result_sha256: Result.hash_rows(rows),
         rows: rows,
         metadata: %{client: :sparql_client}
       }}
    else
      {:error, %Refusal{} = refusal} ->
        {:error, refusal}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           endpoint,
           "SPARQL protocol client returned an unrecognized result",
           %{result: inspect(other)}
         )}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         endpoint,
         "SPARQL protocol query raised",
         %{exception: Exception.message(exception)}
       )}
  end
end
