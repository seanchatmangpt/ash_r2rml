# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Observation do
  @moduledoc "Operator-invoked observation of one bounded external OBDA query execution."

  defstruct [
    :status,
    :standing,
    :system,
    :system_version,
    :evidence_kind,
    :exit_status,
    :command_sha256,
    :query_sha256,
    :mapping_sha256,
    :session_sha256,
    :observation_sha256,
    :output_sha256,
    :output_bytes,
    :row_count,
    :duration_ms,
    :raw_output,
    :capability_receipt,
    :refusal,
    bounded?: true,
    rows: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          system: atom() | String.t(),
          system_version: String.t() | nil,
          evidence_kind: :system_process | :injected_runner,
          exit_status: integer() | nil,
          command_sha256: String.t() | nil,
          query_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          session_sha256: String.t() | nil,
          observation_sha256: String.t() | nil,
          output_sha256: String.t() | nil,
          output_bytes: non_neg_integer() | nil,
          row_count: non_neg_integer() | nil,
          duration_ms: non_neg_integer() | nil,
          raw_output: String.t() | nil,
          capability_receipt: AshR2RML.OBDA.CapabilityReceipt.t() | nil,
          refusal: AshR2RML.Refusal.t() | nil,
          bounded?: boolean(),
          rows: [map()]
        }
end

defmodule AshR2RML.OBDA.Ontop do
  @moduledoc """
  Operator-invoked adapter for Ontop's `query` CLI.

  This module does not start an endpoint and is never called implicitly by the
  compiler. `query/1` executes the real external process. `query/2` exists for
  deterministic unit testing with an injected runner and is permanently marked
  `:test_double_only`; its result must not be attached as a crown/parity witness.

  External execution is bounded by timeout, output bytes, and parsed row count.
  Raw engine output is excluded from observations by default; set
  `retain_raw_output: true` only for explicitly authorized local diagnostics.

  `:prefix_args` allows an operator to place Ontop behind an execution wrapper,
  including the official Docker image, without changing the semantic command.
  """

  alias AshR2RML.{OBDA.Observation, Refusal}
  alias AshR2RML.OBDA.Capabilities

  @default_timeout_ms 30_000
  @default_max_output_bytes 4 * 1024 * 1024
  @default_max_rows 50_000

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

  @doc "Execute Ontop as a real bounded external process."
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
    version = get(opts, :engine_version)
    required_capabilities = get(opts, :required_capabilities, []) |> List.wrap()

    with {:ok, capability_receipt} <- Capabilities.admit(:ontop, version, required_capabilities),
         {:ok, {binary, args}} <- command(opts) do
      query_sha256 = hash_file_or_value(get(opts, :query_path), get(opts, :query))
      mapping_sha256 = hash_file_or_value(get(opts, :mapping_path), get(opts, :mapping))
      command_sha256 = sha256(:erlang.term_to_binary({binary, redact(args)}, [:deterministic]))
      session_sha256 = get(opts, :session_sha256)
      timeout_ms = bounded_integer(get(opts, :timeout_ms), @default_timeout_ms)
      max_output_bytes = bounded_integer(get(opts, :max_output_bytes), @default_max_output_bytes)
      max_rows = bounded_integer(get(opts, :max_rows), @default_max_rows)
      started = System.monotonic_time(:millisecond)

      case run_bounded(runner, binary, args, timeout_ms) do
        {:ok, {output, status}} when is_binary(output) and is_integer(status) ->
          duration_ms = elapsed(started)
          output_bytes = byte_size(output)
          output_sha256 = sha256(output)

          cond do
            output_bytes > max_output_bytes ->
              bounded_failure(
                opts,
                evidence_kind,
                version,
                capability_receipt,
                :REFUSED_RESOURCE_BOUND,
                :obda_output_bytes,
                "OBDA output exceeded the admitted byte bound",
                %{observed: output_bytes, limit: max_output_bytes},
                command_sha256,
                query_sha256,
                mapping_sha256,
                session_sha256,
                status,
                output_sha256,
                output_bytes,
                duration_ms
              )

            status != 0 ->
              execution_failure(
                opts,
                evidence_kind,
                version,
                capability_receipt,
                status,
                command_sha256,
                query_sha256,
                mapping_sha256,
                session_sha256,
                output_sha256,
                output_bytes,
                duration_ms,
                output
              )

            true ->
              rows = parse_csv(output)

              if length(rows) > max_rows do
                bounded_failure(
                  opts,
                  evidence_kind,
                  version,
                  capability_receipt,
                  :REFUSED_RESOURCE_BOUND,
                  :obda_rows,
                  "OBDA result exceeded the admitted row bound",
                  %{observed: length(rows), limit: max_rows},
                  command_sha256,
                  query_sha256,
                  mapping_sha256,
                  session_sha256,
                  status,
                  output_sha256,
                  output_bytes,
                  duration_ms
                )
              else
                standing = if evidence_kind == :system_process, do: :obda_query_observed, else: :test_double_only
                executed_capability_receipt = Capabilities.mark_executed(capability_receipt)

                observation_sha256 =
                  observation_hash(%{
                    system: :ontop,
                    system_version: version,
                    evidence_kind: evidence_kind,
                    exit_status: 0,
                    command_sha256: command_sha256,
                    query_sha256: query_sha256,
                    mapping_sha256: mapping_sha256,
                    session_sha256: session_sha256,
                    output_sha256: output_sha256,
                    output_bytes: output_bytes,
                    row_count: length(rows),
                    capability_receipt_sha256: executed_capability_receipt.receipt_sha256
                  })

                {:ok,
                 %Observation{
                   status: :PARTIAL_ALIVE,
                   standing: standing,
                   system: :ontop,
                   system_version: version,
                   evidence_kind: evidence_kind,
                   exit_status: 0,
                   command_sha256: command_sha256,
                   query_sha256: query_sha256,
                   mapping_sha256: mapping_sha256,
                   session_sha256: session_sha256,
                   observation_sha256: observation_sha256,
                   output_sha256: output_sha256,
                   output_bytes: output_bytes,
                   row_count: length(rows),
                   duration_ms: duration_ms,
                   raw_output: retained_output(opts, output),
                   capability_receipt: executed_capability_receipt,
                   bounded?: true,
                   rows: rows
                 }}
              end
          end

        {:ok, _unexpected} ->
          runner_failure(
            evidence_kind,
            version,
            capability_receipt,
            :runner_contract,
            command_sha256,
            query_sha256,
            mapping_sha256,
            session_sha256,
            elapsed(started)
          )

        {:error, :timeout} ->
          bounded_failure(
            opts,
            evidence_kind,
            version,
            capability_receipt,
            :REFUSED_RESOURCE_BOUND,
            :obda_timeout,
            "OBDA execution exceeded the admitted timeout",
            %{limit_ms: timeout_ms},
            command_sha256,
            query_sha256,
            mapping_sha256,
            session_sha256,
            nil,
            nil,
            nil,
            elapsed(started)
          )

        {:error, _reason} ->
          runner_failure(
            evidence_kind,
            version,
            capability_receipt,
            :runner_crashed,
            command_sha256,
            query_sha256,
            mapping_sha256,
            session_sha256,
            elapsed(started)
          )
      end
    else
      {:error, %Refusal{} = refusal} ->
        {:error,
         %Observation{
           status: :REFUSED,
           standing: :invalid_obda_invocation,
           system: :ontop,
           system_version: version,
           evidence_kind: evidence_kind,
           refusal: refusal,
           bounded?: true,
           rows: []
         }}
    end
  end

  defp run_bounded(runner, binary, args, timeout_ms) do
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        result =
          try do
            {:runner_result, runner.(binary, args, [])}
          rescue
            _exception -> {:runner_error, :exception}
          catch
            _kind, _reason -> {:runner_error, :abnormal_exit}
          end

        send(parent, {ref, result})
      end)

    receive do
      {^ref, {:runner_result, value}} ->
        Process.demonitor(monitor, [:flush])
        {:ok, value}

      {^ref, {:runner_error, reason}} ->
        Process.demonitor(monitor, [:flush])
        {:error, reason}

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        {:error, :runner_crashed}
    after
      timeout_ms ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
        after
          100 -> :ok
        end

        {:error, :timeout}
    end
  end

  defp bounded_failure(
         opts,
         evidence_kind,
         version,
         capability_receipt,
         code,
         subject,
         detail,
         evidence,
         command_sha256,
         query_sha256,
         mapping_sha256,
         session_sha256,
         exit_status,
         output_sha256,
         output_bytes,
         duration_ms
       ) do
    refusal = Refusal.new(code, subject, detail, evidence)

    {:error,
     %Observation{
       status: :BLOCKED,
       standing: :obda_bound_exhausted,
       system: :ontop,
       system_version: version,
       evidence_kind: evidence_kind,
       exit_status: exit_status,
       command_sha256: command_sha256,
       query_sha256: query_sha256,
       mapping_sha256: mapping_sha256,
       session_sha256: session_sha256,
       output_sha256: output_sha256,
       output_bytes: output_bytes,
       duration_ms: duration_ms,
       raw_output: if(output_sha256, do: retained_output(opts, nil), else: nil),
       capability_receipt: capability_receipt,
       refusal: refusal,
       bounded?: true,
       rows: []
     }}
  end

  defp execution_failure(
         opts,
         evidence_kind,
         version,
         capability_receipt,
         status,
         command_sha256,
         query_sha256,
         mapping_sha256,
         session_sha256,
         output_sha256,
         output_bytes,
         duration_ms,
         output
       ) do
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
       system_version: version,
       evidence_kind: evidence_kind,
       exit_status: status,
       command_sha256: command_sha256,
       query_sha256: query_sha256,
       mapping_sha256: mapping_sha256,
       session_sha256: session_sha256,
       output_sha256: output_sha256,
       output_bytes: output_bytes,
       duration_ms: duration_ms,
       raw_output: retained_output(opts, output),
       capability_receipt: capability_receipt,
       refusal: refusal,
       bounded?: true,
       rows: []
     }}
  end

  defp runner_failure(
         evidence_kind,
         version,
         capability_receipt,
         class,
         command_sha256,
         query_sha256,
         mapping_sha256,
         session_sha256,
         duration_ms
       ) do
    refusal =
      Refusal.new(
        :REFUSED_OBDA_EXECUTION,
        :ontop,
        "Ontop process could not be executed within the admitted runner contract",
        %{error_class: class}
      )

    {:error,
     %Observation{
       status: :BLOCKED,
       standing: :obda_execution_unavailable,
       system: :ontop,
       system_version: version,
       evidence_kind: evidence_kind,
       exit_status: nil,
       command_sha256: command_sha256,
       query_sha256: query_sha256,
       mapping_sha256: mapping_sha256,
       session_sha256: session_sha256,
       duration_ms: duration_ms,
       capability_receipt: capability_receipt,
       refusal: refusal,
       bounded?: true,
       rows: []
     }}
  end

  defp observation_hash(fields) do
    fields
    |> :erlang.term_to_binary([:deterministic])
    |> sha256()
  end

  defp retained_output(opts, output) do
    if get(opts, :retain_raw_output, false), do: output, else: nil
  end

  defp bounded_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp bounded_integer(_value, default), do: default

  defp elapsed(started), do: max(System.monotonic_time(:millisecond) - started, 0)

  defp required(opts, key) do
    case get(opts, key) do
      value when is_binary(value) and value != "" ->
        {:ok, value}

      value ->
        {:error,
         Refusal.new(
           :REFUSED_OBDA_EXECUTION,
           :ontop,
           "missing required Ontop option #{key}",
           %{present?: not is_nil(value)}
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