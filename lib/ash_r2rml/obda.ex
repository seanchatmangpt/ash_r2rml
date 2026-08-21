# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Observation do
  @moduledoc "Operator-invoked observation of one external OBDA query execution."

  defstruct [
    :status,
    :standing,
    :system,
    :evidence_kind,
    :exit_status,
    :command_sha256,
    :query_sha256,
    :mapping_sha256,
    :raw_output,
    :refusal,
    rows: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          system: atom() | String.t(),
          evidence_kind: :system_process | :injected_runner,
          exit_status: integer() | nil,
          command_sha256: String.t() | nil,
          query_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          raw_output: String.t() | nil,
          refusal: AshR2RML.Refusal.t() | nil,
          rows: [map()]
        }
end

defmodule AshR2RML.OBDA.Ontop do
  @moduledoc """
  Operator-invoked adapter for Ontop's `query` CLI.

  This module does not start an endpoint and is never called implicitly by the
  compiler. `query/1` executes the real external process. `query/2` exists for
  deterministic unit testing with an injected runner and is permanently marked
  `:test_double_only`; its result must not be attached as a parity witness.

  `:prefix_args` allows an operator to place Ontop behind an execution wrapper,
  including the official Docker image, without changing the semantic command.
  """

  alias AshR2RML.{OBDA.Observation, Refusal}

  @spec command(keyword() | map()) :: {:ok, {String.t(), [String.t()]}} | {:error, Refusal.t()}
  def command(opts) do
    with {:ok, mapping} <- required(opts, :mapping_path),
         {:ok, query} <- required(opts, :query_path) do
      binary = get(opts, :binary, System.get_env("ONTOP_BIN") || "ontop")
      prefix_args = get(opts, :prefix_args, []) |> List.wrap()

      args =
        (prefix_args ++ ["query", "-m", mapping, "-q", query])
        |> append_option("-p", get(opts, :properties_path))
        |> append_option("-t", get(opts, :ontology_path))
        |> append_option("--db-url", get(opts, :db_url))
        |> append_option("-u", get(opts, :db_user))
        |> append_option("--db-password", get(opts, :db_password))
        |> append_option("--db-driver", get(opts, :db_driver))
        |> append_option("-a", get(opts, :facts_path))
        |> append_option("-l", get(opts, :lenses_path))
        |> append_option("--sparql-rules", get(opts, :sparql_rules_path))

      {:ok, {to_string(binary), Enum.map(args, &to_string/1)}}
    end
  end

  @doc "Execute Ontop as a real external process."
  @spec query(keyword() | map()) :: {:ok, Observation.t()} | {:error, Observation.t()}
  def query(opts), do: execute(opts, &System.cmd/3, :system_process)

  @doc "Execute through an injected runner for unit tests; never a crown/parity witness."
  @spec query(keyword() | map(), function()) :: {:ok, Observation.t()} | {:error, Observation.t()}
  def query(opts, runner) when is_function(runner, 3), do: execute(opts, runner, :injected_runner)

  @doc "Parse Ontop SELECT CSV output into deterministic string-keyed row maps."
  @spec parse_csv(String.t()) :: [map()]
  def parse_csv(output) when is_binary(output) do
    clean_lines =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing(&1, "\r"))
      |> Enum.reject(fn line -> log_or_ignorable_line?(line) end)

    records =
      clean_lines
      |> Enum.map(fn line -> parse_csv_line(line) end)
      |> Enum.reject(&(&1 == [] or Enum.all?(&1, fn field -> field == "" end)))

    case records do
      [] ->
        []

      [headers | rows] ->
        clean_headers = Enum.map(headers, fn field -> clean_field(field) end)

        Enum.map(rows, fn row ->
          clean_fields = Enum.map(row, fn field -> clean_field(field) end)
          pairs = Enum.zip(clean_headers, clean_fields)
          Map.new(pairs)
        end)
    end
  end

  defp log_or_ignorable_line?(line) do
    trimmed = String.trim(line)

    trimmed == "" or
      String.starts_with?(trimmed, "Picked up ") or
      String.starts_with?(trimmed, "SLF4J:") or
      String.starts_with?(trimmed, "target atoms:") or
      String.starts_with?(trimmed, "source query:") or
      String.starts_with?(trimmed, "WARNING:") or
      String.starts_with?(trimmed, "WARN:") or
      String.starts_with?(trimmed, "INFO:") or
      String.starts_with?(trimmed, "DEBUG:") or
      String.starts_with?(trimmed, "ERROR:") or
      String.contains?(trimmed, "|-INFO") or
      String.contains?(trimmed, "|-WARN") or
      String.contains?(trimmed, "|-ERROR") or
      String.contains?(trimmed, "|-DEBUG") or
      String.contains?(trimmed, "it.unibz.inf.ontop") or
      String.contains?(trimmed, "org.eclipse.rdf4j") or
      String.contains?(trimmed, "ch.qos.logback") or
      Regex.match?(~r/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, trimmed)
  end

  defp parse_csv_line(line) do
    line
    |> String.replace_prefix("\uFEFF", "")
    |> tokenize_csv_line([], "", false)
  end

  defp tokenize_csv_line("", acc, current, _in_quotes) do
    Enum.reverse([current | acc])
  end

  defp tokenize_csv_line("\"\"" <> rest, acc, current, true) do
    tokenize_csv_line(rest, acc, current <> "\"", true)
  end

  defp tokenize_csv_line("\"" <> rest, acc, current, in_quotes) do
    tokenize_csv_line(rest, acc, current, not in_quotes)
  end

  defp tokenize_csv_line("," <> rest, acc, current, false) do
    tokenize_csv_line(rest, [current | acc], "", false)
  end

  defp tokenize_csv_line(<<char::utf8, rest::binary>>, acc, current, in_quotes) do
    tokenize_csv_line(rest, acc, current <> <<char::utf8>>, in_quotes)
  end

  defp clean_field(field) do
    trimmed = String.trim(field)

    if String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") and byte_size(trimmed) >= 2 do
      trimmed |> String.slice(1..-2//1) |> String.trim()
    else
      trimmed
    end
  end

  defp execute(opts, runner, evidence_kind) do
    with {:ok, {binary, args}} <- command(opts) do
      query_sha256 = hash_file_or_value(get(opts, :query_path), get(opts, :query))
      mapping_sha256 = hash_file_or_value(get(opts, :mapping_path), get(opts, :mapping))
      command_sha256 = sha256(:erlang.term_to_binary({binary, redact(args)}, [:deterministic]))

      try do
        case runner.(binary, args, []) do
          {output, 0} ->
            standing = if evidence_kind == :system_process, do: :obda_query_observed, else: :test_double_only

            {:ok,
             %Observation{
               status: :PARTIAL_ALIVE,
               standing: standing,
               system: :ontop,
               evidence_kind: evidence_kind,
               exit_status: 0,
               command_sha256: command_sha256,
               query_sha256: query_sha256,
               mapping_sha256: mapping_sha256,
               raw_output: output,
               rows: parse_csv(output)
             }}

          {output, status} when is_integer(status) ->
            refusal =
              Refusal.new(
                :REFUSED_OBDA_EXECUTION,
                :ontop,
                "Ontop query exited non-zero",
                %{exit_status: status}
              )

            {:error,
             %Observation{
               status: :BLOCKED,
               standing: :obda_execution_failed,
               system: :ontop,
               evidence_kind: evidence_kind,
               exit_status: status,
               command_sha256: command_sha256,
               query_sha256: query_sha256,
               mapping_sha256: mapping_sha256,
               raw_output: output,
               refusal: refusal,
               rows: []
             }}
        end
      rescue
        exception ->
          refusal =
            Refusal.new(
              :REFUSED_OBDA_EXECUTION,
              :ontop,
              "Ontop process could not be executed",
              %{reason: Exception.message(exception)}
            )

          {:error,
           %Observation{
             status: :BLOCKED,
             standing: :obda_execution_unavailable,
             system: :ontop,
             evidence_kind: evidence_kind,
             exit_status: nil,
             command_sha256: command_sha256,
             query_sha256: query_sha256,
             mapping_sha256: mapping_sha256,
             refusal: refusal,
             rows: []
           }}
      end
    else
      {:error, refusal} ->
        {:error,
         %Observation{
           status: :REFUSED,
           standing: :invalid_obda_invocation,
           system: :ontop,
           evidence_kind: evidence_kind,
           exit_status: nil,
           command_sha256: nil,
           query_sha256: nil,
           mapping_sha256: nil,
           refusal: refusal,
           rows: []
         }}
    end
  end

  defp append_option(args, _flag, nil), do: args
  defp append_option(args, flag, value), do: args ++ [flag, to_string(value)]

  defp required(opts, key) do
    case get(opts, key) do
      nil ->
        {:error,
         Refusal.new(
           :REFUSED_MISSING_MAPPING,
           :ontop,
           "Missing required Ontop argument :#{key}",
           %{missing_key: key}
         )}

      value ->
        {:ok, to_string(value)}
    end
  end

  defp get(opts, key, default \\ nil)
  defp get(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp get(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp hash_file_or_value(path, value) do
    cond do
      is_binary(path) and File.exists?(path) ->
        sha256(File.read!(path))

      is_binary(value) ->
        sha256(value)

      true ->
        nil
    end
  end

  defp sha256(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp redact(args) do
    Enum.chunk_every(args, 2, 1, [nil])
    |> Enum.map(fn
      ["--db-password", _pass] -> "--db-password [REDACTED]"
      [other, _] -> other
      [single] -> single
    end)
  end
end
