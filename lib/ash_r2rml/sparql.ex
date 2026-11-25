# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# SPARQL value types: Query (admission), Observation (evidence) and Result
# (normalization). Execution strategies live in sparql/local.ex
# (AshR2RML.SPARQL.Local) and sparql/protocol.ex (AshR2RML.SPARQL.Protocol,
# with host vetting in sparql/protocol/host.ex).

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

  @doc """
  Reads a SPARQL query from `file_path` and admits it.

  An unreadable file returns `:REFUSED_UNPROVEN_EQUIVALENCE` with the path in
  the evidence.
  """
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

  @doc """
  Admits query text, a parsed `SPARQL.Query`, or an already admitted `t()`.

  The identity (`sha256`) covers the exact lexical query text. Text that
  SPARQL.ex rejects, and any other input shape, returns
  `:REFUSED_UNPROVEN_EQUIVALENCE`.
  """
  @spec admit(t() | String.t() | Elixir.SPARQL.Query.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def admit(%__MODULE__{} = admitted), do: {:ok, admitted}

  def admit(%Elixir.SPARQL.Query{query_string: source} = parsed) when is_binary(source) do
    admit_parsed(parsed, source)
  end

  def admit(source) when is_binary(source), do: parse_source(source)

  def admit(other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_query,
       "expected SPARQL query text or SPARQL.Query",
       %{got: inspect(other)}
     )}
  end

  defp parse_source(source) do
    case Elixir.SPARQL.Query.new(source, default_prefixes: nil) do
      %Elixir.SPARQL.Query{} = parsed ->
        admit_parsed(parsed, source)

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
    exception in [ArgumentError, FunctionClauseError, MatchError, RuntimeError, Protocol.UndefinedError] ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :sparql_query,
         "SPARQL.ex raised during language admission",
         %{reason: Exception.message(exception), exception: inspect(exception.__struct__)}
       )}
  end

  # Admits an already parsed `SPARQL.Query` under the lexical `source` it came from.
  defp admit_parsed(%Elixir.SPARQL.Query{} = parsed, source) when is_binary(source) do
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

  @default_max_rows 100_000

  @doc "Default row bound applied to local and protocol results."
  @spec default_max_rows() :: pos_integer()
  def default_max_rows, do: @default_max_rows

  @doc "Fails closed with `:REFUSED_RESOURCE_BOUND` when `rows` exceeds `max_rows`."
  @spec bound({:ok, atom(), list()} | term(), term(), pos_integer()) :: term()
  def bound({:ok, _kind, rows} = ok, subject, max_rows)
      when is_integer(max_rows) and max_rows > 0 do
    if length(rows) > max_rows do
      {:error,
       Refusal.new(
         :REFUSED_RESOURCE_BOUND,
         subject,
         "SPARQL result exceeds the max_rows bound",
         %{max_rows: max_rows, rows: length(rows)}
       )}
    else
      ok
    end
  end

  def bound(other, _subject, _max_rows), do: other

  @doc """
  Normalizes a SPARQL.ex result into `{:ok, kind, rows}`.

  `kind` is `:bindings` (SELECT), `:boolean` (ASK) or `:rdf` (graph results).
  Unsupported shapes return `:REFUSED_UNPROVEN_EQUIVALENCE`.
  """
  @spec normalize(term()) :: {:ok, atom(), list()} | {:error, Refusal.t()}
  def normalize(%Elixir.SPARQL.Query.Result{results: results}) when is_list(results) do
    {:ok, :bindings, Enum.map(results, &normalize_binding/1)}
  end

  def normalize(%Elixir.SPARQL.Query.Result{results: result}) when is_boolean(result) do
    {:ok, :boolean, [%{"ask" => result}]}
  end

  def normalize(data) do
    rows = data |> RDF.Data.statements() |> Enum.map(&normalize_statement/1)
    {:ok, :rdf, rows}
  rescue
    exception in [ArgumentError, FunctionClauseError, Protocol.UndefinedError] ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :sparql_result,
         "unsupported SPARQL result shape",
         %{result: inspect(data), exception: inspect(exception.__struct__)}
       )}
  end

  @doc "SHA-256 (lowercase hex) over the multiset-normalized rows; row order does not matter."
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
  # A relational source can yield the raw lexical numeric string with no
  # datatype tag and no value-space reduction — a `NUMERIC(6,2)` column
  # round-trips as the literal text "45.50". Comparing a value-space-reduced
  # Decimal against an untouched lexical string produced spurious parity
  # mismatches (`receipt.verified? == false`) for any decimal literal whose
  # lexical scale is not preserved by its numeric value (observed: xsd:decimal
  # "45.50", "30.00", "50000.00" reduced to "45.5"/"30"/"50000"). Preserve the
  # original lexical form for decimal literals so every observation path is
  # compared on the same text.
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
    _error in [ArgumentError, FunctionClauseError, Protocol.UndefinedError] -> value
  end
end
