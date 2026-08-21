# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ML.SPARQL.Query do
  @moduledoc """
  Admitted SPARQL query identity.

  Query parsing is delegated to SPARQL.ex. The SHA-256 identity intentionally
  covers the exact lexical query supplied by the caller; AshR2ML does not claim
  semantic canonicalization of arbitrary SPARQL algebra.
  """

  alias AshR2ML.Refusal

  @enforce_keys [:source, :parsed, :form, :sha256]
  defstruct [:source, :parsed, :form, :sha256]

  @type t :: %__MODULE__{
          source: String.t(),
          parsed: Elixir.SPARQL.Query.t(),
          form: atom(),
          sha256: String.t()
        }

  @spec admit(String.t() | Elixir.SPARQL.Query.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def admit(%Elixir.SPARQL.Query{} = parsed) do
    source = parsed.query_string || to_string(parsed)
    {:ok, %__MODULE__{source: source, parsed: parsed, form: parsed.form, sha256: sha256(source)}}
  end

  def admit(source) when is_binary(source) do
    case Elixir.SPARQL.Query.new(source, default_prefixes: nil) do
      %Elixir.SPARQL.Query{} = parsed ->
        {:ok, %__MODULE__{source: source, parsed: parsed, form: parsed.form, sha256: sha256(source)}}

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_query,
           "SPARQL.ex refused the query during language admission",
           %{reason: inspect(reason)}
         )}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_query,
           "SPARQL.ex did not return an admitted query",
           %{result: inspect(other)}
         )}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :sparql_query,
         "SPARQL query parsing raised",
         %{exception: Exception.message(exception)}
       )}
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

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

defmodule AshR2ML.SPARQL.Observation do
  @moduledoc "Evidence-bounded observation from one explicitly selected SPARQL execution strategy."

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
          strategy: :local_rdf | :protocol | :ontop_cli,
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

defmodule AshR2ML.SPARQL.Result do
  @moduledoc "Normalizes RDF-Elixir SPARQL results into deterministic parity rows."

  alias AshR2ML.Refusal

  @spec normalize(term()) :: {:ok, atom(), list()} | {:error, Refusal.t()}
  def normalize(%Elixir.SPARQL.Query.Result{results: results}) when is_list(results) do
    {:ok, :bindings, Enum.map(results, &normalize_binding/1)}
  end

  def normalize(%Elixir.SPARQL.Query.Result{results: result}) when is_boolean(result) do
    {:ok, :boolean, [%{"ask" => result}]}
  end

  def normalize(data) do
    try do
      rows =
        data
        |> RDF.Data.statements()
        |> Enum.map(&normalize_statement/1)

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
    |> AshR2ml.Parity.normalize_multiset()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_binding(binding) when is_map(binding) do
    Map.new(binding, fn {key, value} -> {to_string(key), normalize_term(value)} end)
  end

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

  defp normalize_term(value) do
    if RDF.Term.term?(value) do
      RDF.Term.value(value)
    else
      value
    end
  rescue
    _ -> value
  end
end

defmodule AshR2ML.SPARQL.Local do
  @moduledoc "Explicit local SPARQL.ex execution against an RDF.ex data structure."

  alias AshR2ML.{Refusal, SPARQL}

  @spec query(RDF.Data.Source.t(), String.t() | SPARQL.Query.t()) ::
          {:ok, SPARQL.Observation.t()} | {:error, Refusal.t()}
  def query(data, query) do
    with {:ok, admitted} <- SPARQL.Query.admit(query) do
      try do
        result = Elixir.SPARQL.execute_query(data, admitted.parsed)

        with {:ok, result_kind, rows} <- SPARQL.Result.normalize(result) do
          {:ok,
           %SPARQL.Observation{
             strategy: :local_rdf,
             query_sha256: admitted.sha256,
             query_form: admitted.form,
             status: :PARTIAL_ALIVE,
             standing: :observed_local_rdf_execution,
             evidence_kind: :in_memory_execution,
             result_kind: result_kind,
             result_sha256: SPARQL.Result.hash_rows(rows),
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
end

defmodule AshR2ML.SPARQL.Protocol do
  @moduledoc """
  Read-only SPARQL Protocol execution through SPARQL.Client.

  This module intentionally exposes query operations only. SPARQL Update is not
  delegated because AshR2ML verification does not acquire remote mutation
  authority from the presence of a protocol client dependency.
  """

  alias AshR2ML.{Refusal, SPARQL}

  @spec query(String.t(), String.t() | SPARQL.Query.t(), keyword()) ::
          {:ok, SPARQL.Observation.t()} | {:error, term()}
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
  def query_with(endpoint, query, opts, client_fun)
      when is_binary(endpoint) and is_function(client_fun, 3) do
    do_query(endpoint, query, opts, client_fun, :injected_client, :test_double_only)
  end

  defp do_query(endpoint, query, opts, client_fun, evidence_kind, standing) do
    with {:ok, admitted} <- SPARQL.Query.admit(query),
         {:ok, result} <- client_fun.(admitted.parsed, endpoint, opts),
         {:ok, result_kind, rows} <- SPARQL.Result.normalize(result) do
      {:ok,
       %SPARQL.Observation{
         strategy: :protocol,
         query_sha256: admitted.sha256,
         query_form: admitted.form,
         status: :PARTIAL_ALIVE,
         standing: standing,
         evidence_kind: evidence_kind,
         endpoint: endpoint,
         result_kind: result_kind,
         result_sha256: SPARQL.Result.hash_rows(rows),
         rows: rows,
         metadata: %{client: :sparql_client}
       }}
    else
      {:error, %Refusal{} = refusal} -> {:error, refusal}
      {:error, reason} -> {:error, reason}
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

defmodule AshR2ML.SPARQL.Plan do
  @moduledoc "DfCM execution plan preserving all currently lawful SPARQL execution candidates."

  @enforce_keys [:query, :candidates]
  defstruct [:query, :selected, candidates: [], context: %{}]

  @type strategy :: :local_rdf | :protocol | :ontop_cli
  @type t :: %__MODULE__{
          query: AshR2ML.SPARQL.Query.t(),
          selected: strategy() | nil,
          candidates: [strategy()],
          context: map()
        }
end

defmodule AshR2ML.SPARQL do
  @moduledoc """
  DfCM SPARQL execution calculus.

  Local RDF.ex execution, SPARQL Protocol execution, and the existing Ontop CLI
  path remain distinct lawful candidates. When multiple candidates are present,
  no strategy is selected unless the caller explicitly closes the choice.
  """

  alias AshR2ML.{Refusal, SPARQL}

  @spec explore(String.t() | SPARQL.Query.t(), keyword()) ::
          {:ok, SPARQL.Plan.t()} | {:error, Refusal.t()}
  def explore(query, opts \\ []) do
    with {:ok, admitted} <- SPARQL.Query.admit(query) do
      candidates =
        []
        |> maybe_candidate(Keyword.has_key?(opts, :data), :local_rdf)
        |> maybe_candidate(is_binary(Keyword.get(opts, :endpoint)), :protocol)
        |> maybe_candidate(not is_nil(Keyword.get(opts, :ontop)), :ontop_cli)

      case candidates do
        [] ->
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :sparql_execution,
             "no SPARQL execution candidate was supplied",
             %{expected: [:data, :endpoint, :ontop]}
           )}

        _ ->
          explicit = Keyword.get(opts, :strategy)

          cond do
            explicit && explicit not in candidates ->
              {:error,
               Refusal.new(
                 :REFUSED_UNPROVEN_EQUIVALENCE,
                 :sparql_execution,
                 "selected SPARQL execution strategy is not available",
                 %{selected: explicit, candidates: candidates}
               )}

            true ->
              selected = explicit || if(length(candidates) == 1, do: hd(candidates))

              {:ok,
               %SPARQL.Plan{
                 query: admitted,
                 candidates: candidates,
                 selected: selected,
                 context: %{
                   data: Keyword.get(opts, :data),
                   endpoint: Keyword.get(opts, :endpoint),
                   client_opts: Keyword.get(opts, :client_opts, []),
                   ontop: Keyword.get(opts, :ontop)
                 }
               }}
          end
      end
    end
  end

  @spec execute(SPARQL.Plan.t()) :: {:ok, SPARQL.Observation.t()} | {:error, term()}
  def execute(%SPARQL.Plan{selected: nil} = plan) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_execution,
       "multiple lawful SPARQL execution candidates remain; explicit selection is required",
       %{candidates: plan.candidates}
     )}
  end

  def execute(%SPARQL.Plan{selected: :local_rdf, query: query, context: %{data: data}}) do
    SPARQL.Local.query(data, query)
  end

  def execute(%SPARQL.Plan{selected: :protocol, query: query, context: context}) do
    SPARQL.Protocol.query(context.endpoint, query, context.client_opts)
  end

  def execute(%SPARQL.Plan{selected: :ontop_cli, query: query, context: %{ontop: ontop}})
      when is_map(ontop) do
    opts = ontop |> Map.put_new(:query, query.source)

    with {:ok, observation} <- AshR2ML.OBDA.Ontop.query(opts) do
      rows = observation.rows

      {:ok,
       %SPARQL.Observation{
         strategy: :ontop_cli,
         query_sha256: query.sha256,
         query_form: query.form,
         status: observation.status,
         standing: observation.standing,
         evidence_kind: observation.evidence_kind,
         result_kind: :bindings,
         result_sha256: SPARQL.Result.hash_rows(rows),
         rows: rows,
         metadata: %{
           engine: :ontop,
           mapping_sha256: observation.mapping_sha256
         }
       }}
    end
  end

  def execute(%SPARQL.Plan{} = plan) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_execution,
       "selected SPARQL execution strategy lacks its required execution context",
       %{selected: plan.selected, candidates: plan.candidates}
     )}
  end

  defp maybe_candidate(values, true, candidate), do: values ++ [candidate]
  defp maybe_candidate(values, false, _candidate), do: values
end

defmodule AshR2ML.JSONLD do
  @moduledoc """
  JSON-LD 1.1 projection and ingestion through JSON-LD.ex.

  JSON-LD and Turtle are alternate RDF serializations feeding the same SHACL
  admission boundary. Remote contexts are refused by default because network
  context resolution would otherwise make ontology compilation depend on
  ambient mutable state; callers must explicitly opt in to remote contexts.
  """

  alias AshR2ML.Refusal

  @spec to_rdf(String.t() | map() | list(), keyword()) :: {:ok, RDF.Dataset.t()} | {:error, Refusal.t()}
  def to_rdf(input, opts \\ []) do
    with {:ok, document} <- decode_document(input),
         :ok <- admit_contexts(document, opts) do
      {:ok, JSON.LD.to_rdf(document)}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :jsonld,
         "JSON-LD.ex failed to project the document to RDF",
         %{exception: Exception.message(exception)}
       )}
  end

  @spec ingest(String.t() | map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def ingest(input, opts \\ []) do
    source = if is_binary(input), do: input, else: Jason.encode!(input)

    with {:ok, data} <- to_rdf(input, opts) do
      AshR2ml.Ingestion.from_graph(
        data,
        Keyword.put_new(opts, :source_sha256, sha256(source))
      )
    end
  end

  @spec compile(String.t() | map() | list(), keyword()) ::
          {:ok, AshR2ML.Mapping.Bundle.t()} | {:error, term()}
  def compile(input, opts \\ []) do
    with {:ok, profile} <- ingest(input, opts) do
      AshR2ML.Compiler.compile_profile(profile)
    end
  end

  @spec expand(String.t() | map() | list(), keyword()) :: {:ok, term()} | {:error, Refusal.t()}
  def expand(input, opts \\ []) do
    with {:ok, document} <- decode_document(input),
         :ok <- admit_contexts(document, opts) do
      {:ok, JSON.LD.expand(document)}
    end
  rescue
    exception -> jsonld_error(:expand, exception)
  end

  @spec compact(String.t() | map() | list(), map() | String.t(), keyword()) ::
          {:ok, map()} | {:error, Refusal.t()}
  def compact(input, context, opts \\ []) do
    with {:ok, document} <- decode_document(input),
         :ok <- admit_contexts(document, opts),
         :ok <- admit_contexts(%{"@context" => context}, opts) do
      {:ok, JSON.LD.compact(document, context)}
    end
  rescue
    exception -> jsonld_error(:compact, exception)
  end

  @spec encode_rdf(RDF.Data.Source.t(), keyword()) :: {:ok, String.t()} | {:error, Refusal.t()}
  def encode_rdf(data, opts \\ []) do
    try do
      document = JSON.LD.from_rdf(data)

      document =
        case Keyword.get(opts, :context) do
          nil -> document
          context ->
            case admit_contexts(%{"@context" => context}, opts) do
              :ok -> JSON.LD.compact(document, context)
              {:error, refusal} -> throw({:refusal, refusal})
            end
        end

      json_opts = if Keyword.get(opts, :pretty, true), do: [pretty: true], else: []

      case Jason.encode(document, json_opts) do
        {:ok, json} -> {:ok, json}
        {:error, reason} -> jsonld_error(:encode, reason)
      end
    catch
      {:refusal, refusal} -> {:error, refusal}
    rescue
      exception -> jsonld_error(:encode, exception)
    end
  end

  defp decode_document(input) when is_map(input) or is_list(input), do: {:ok, input}

  defp decode_document(input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, document} -> {:ok, document}
      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :jsonld,
           "invalid JSON-LD JSON syntax",
           %{reason: inspect(reason)}
         )}
    end
  end

  defp decode_document(other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :jsonld,
       "expected decoded JSON-LD object/list or JSON string",
       %{got: inspect(other)}
     )}
  end

  defp admit_contexts(document, opts) do
    remote = remote_contexts(document) |> Enum.uniq() |> Enum.sort()

    if remote == [] or Keyword.get(opts, :allow_remote_contexts?, false) do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :jsonld_context,
         "remote JSON-LD context resolution is not admitted by default",
         %{remote_contexts: remote, opt_in: :allow_remote_contexts?}
       )}
    end
  end

  defp remote_contexts(%{} = map) do
    Enum.flat_map(map, fn
      {"@context", value} -> context_urls(value) ++ remote_contexts(value)
      {"@import", value} -> context_urls(value) ++ remote_contexts(value)
      {_key, value} -> remote_contexts(value)
    end)
  end

  defp remote_contexts(list) when is_list(list), do: Enum.flat_map(list, &remote_contexts/1)
  defp remote_contexts(_), do: []

  # Only a string/list occupying @context or @import is a remote context reference.
  # IRI-valued term definitions inside an inline context map are ordinary mappings.
  defp context_urls(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> [value]
      _ -> []
    end
  end

  defp context_urls(list) when is_list(list), do: Enum.flat_map(list, &context_urls/1)
  defp context_urls(_), do: []

  defp jsonld_error(operation, exception) do
    reason = if is_exception(exception), do: Exception.message(exception), else: inspect(exception)

    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :jsonld,
       "JSON-LD #{operation} failed",
       %{reason: reason}
     )}
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
