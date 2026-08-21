# SPDX-FileCopyrightText: 2026 ash_r2ml contributors <https://github.com/seanchatmangpt/ash_r2ml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2ml.OBDA.Observation do
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
          refusal: AshR2ml.Refusal.t() | nil,
          rows: [map()]
        }
end

defmodule AshR2ml.OBDA.Ontop do
  @moduledoc """
  Operator-invoked adapter for Ontop's `query` CLI.

  This module does not start an endpoint and is never called implicitly by the
  compiler. `query/1` executes the real external process. `query/2` exists for
  deterministic unit testing with an injected runner and is permanently marked
  `:test_double_only`; its result must not be attached as a parity witness.

  Ontop accepts standards-valid R2RML through `-m/--mapping`, a SPARQL SELECT
  query through `-q/--query`, and either a properties file or explicit database
  options. The CLI returns CSV, which this adapter normalizes to string-keyed maps.
  """

  alias AshR2ml.{OBDA.Observation, Refusal}

  @spec command(keyword() | map()) :: {:ok, {String.t(), [String.t()]}} | {:error, Refusal.t()}
  def command(opts) do
    with {:ok, mapping} <- required(opts, :mapping_path),
         {:ok, query} <- required(opts, :query_path) do
      binary = get(opts, :binary, System.get_env("ONTOP_BIN") || "ontop")

      args =
        ["query", "-m", mapping, "-q", query]
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
    records =
      output
      |> String.replace_prefix("\uFEFF", "")
      |> String.to_charlist()
      |> parse_csv_chars([], [], [], false)
      |> Enum.reverse()
      |> Enum.reject(&(&1 == [] or Enum.all?(&1, fn field -> field == "" end)))

    case records do
      [] -> []
      [headers | rows] -> Enum.map(rows, fn row -> Map.new(Enum.zip(headers, row)) end)
    end
  end

  defp execute(opts, runner, evidence_kind) do
    with {:ok, {binary, args}} <- command(opts) do
      query_sha256 = hash_file_or_value(get(opts, :query_path), get(opts, :query))
      mapping_sha256 = hash_file_or_value(get(opts, :mapping_path), get(opts, :mapping))
      command_sha256 = sha256(:erlang.term_to_binary({binary, redact(args)}, [:deterministic]))

      try do
        case runner.(binary, args, stderr_to_stdout: true) do
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
           refusal: refusal,
           rows: []
         }}
    end
  end

  defp required(opts, key) do
    case get(opts, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value ->
        {:error,
         Refusal.new(
           :REFUSED_OBDA_EXECUTION,
           :ontop,
           "missing required Ontop option #{key}",
           %{value: value}
         )}
    end
  end

  defp append_option(args, _flag, nil), do: args
  defp append_option(args, _flag, ""), do: args
  defp append_option(args, flag, value), do: args ++ [flag, value]

  defp redact(args), do: redact(args, [])
  defp redact([], acc), do: Enum.reverse(acc)
  defp redact(["--db-password", _password | rest], acc), do: redact(rest, ["***", "--db-password" | acc])
  defp redact([value | rest], acc), do: redact(rest, [value | acc])

  defp hash_file_or_value(path, fallback) when is_binary(path) do
    case File.read(path) do
      {:ok, value} -> sha256(value)
      _ -> if(is_binary(fallback), do: sha256(fallback), else: nil)
    end
  end

  defp hash_file_or_value(_, fallback) when is_binary(fallback), do: sha256(fallback)
  defp hash_file_or_value(_, _), do: nil

  defp get(opts, key, default \\ nil) when is_list(opts), do: Keyword.get(opts, key, default)

  defp get(opts, key, default) when is_map(opts) do
    Map.get(opts, key, Map.get(opts, Atom.to_string(key), default))
  end

  defp parse_csv_chars([], field, row, rows, _quoted), do: finish_csv(field, row, rows)

  defp parse_csv_chars([?", ?" | rest], field, row, rows, true),
    do: parse_csv_chars(rest, [?" | field], row, rows, true)

  defp parse_csv_chars([?" | rest], field, row, rows, true),
    do: parse_csv_chars(rest, field, row, rows, false)

  defp parse_csv_chars([?" | rest], [], row, rows, false),
    do: parse_csv_chars(rest, [], row, rows, true)

  defp parse_csv_chars([44 | rest], field, row, rows, false),
    do: parse_csv_chars(rest, [], [csv_field(field) | row], rows, false)

  defp parse_csv_chars([?\r, ?\n | rest], field, row, rows, false) do
    completed = Enum.reverse([csv_field(field) | row])
    parse_csv_chars(rest, [], [], [completed | rows], false)
  end

  defp parse_csv_chars([?\n | rest], field, row, rows, false) do
    completed = Enum.reverse([csv_field(field) | row])
    parse_csv_chars(rest, [], [], [completed | rows], false)
  end

  defp parse_csv_chars([char | rest], field, row, rows, quoted),
    do: parse_csv_chars(rest, [char | field], row, rows, quoted)

  defp finish_csv([], [], rows), do: rows
  defp finish_csv(field, row, rows), do: [Enum.reverse([csv_field(field) | row]) | rows]

  defp csv_field(chars), do: chars |> Enum.reverse() |> List.to_string()

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
